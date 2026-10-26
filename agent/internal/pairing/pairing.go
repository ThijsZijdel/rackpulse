package pairing

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"math/big"
	"os"
	"time"

	"github.com/en3sis/rackpulse/agent/internal/atomicfile"
)

func generate(certFile, keyFile string) error {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 127))
	if err != nil {
		return err
	}
	now := time.Now()
	template := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: "rackpulse-agent"},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.AddDate(10, 0, 0),
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		return err
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		return err
	}
	if err := atomicfile.Write(keyFile, pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER}), 0o600); err != nil {
		return err
	}
	return atomicfile.Write(certFile, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o644)
}

func EnsureCertificate(certFile, keyFile string) (bool, error) {
	_, certErr := os.Stat(certFile)
	_, keyErr := os.Stat(keyFile)
	if certErr == nil && keyErr == nil {
		if _, err := tls.LoadX509KeyPair(certFile, keyFile); err == nil {
			return false, nil
		}
	}
	return true, generate(certFile, keyFile)
}

func LoadCertificate(certFile, keyFile string) (tls.Certificate, string, error) {
	pair, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return pair, "", err
	}
	if len(pair.Certificate) == 0 {
		return pair, "", errors.New("no certificate in " + certFile)
	}
	return pair, Fingerprint(pair.Certificate[0]), nil
}

func Fingerprint(der []byte) string {
	sum := sha256.Sum256(der)
	return hex.EncodeToString(sum[:])
}

func ValidNonce(nonce string) bool {
	if len(nonce) != 64 {
		return false
	}
	_, err := hex.DecodeString(nonce)
	return err == nil
}

func Proof(token, nonce, certFingerprint string) string {
	mac := hmac.New(sha256.New, []byte(token))
	mac.Write([]byte("rackpulse-agent-v1|" + nonce + "|" + certFingerprint))
	return hex.EncodeToString(mac.Sum(nil))
}
