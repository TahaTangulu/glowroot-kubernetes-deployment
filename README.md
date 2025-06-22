# Glowroot APM Kubernetes Deployment

Bu proje, Glowroot Application Performance Monitoring (APM) aracını Kubernetes test ortamında çalıştırmak için gerekli tüm kaynakları içerir.

## 📋 İçindekiler

- [Genel Bakış](#genel-bakış)
- [Özellikler](#özellikler)
- [Gereksinimler](#gereksinimler)
- [Kurulum](#kurulum)
- [Konfigürasyon](#konfigürasyon)
- [Kullanım](#kullanım)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Güvenlik](#güvenlik)

## 🎯 Genel Bakış

Glowroot, Java uygulamalarının performansını izlemek için kullanılan hafif ve güçlü bir APM aracıdır. Bu deployment, Kubernetes ortamında Glowroot'u çalıştırmak için gerekli tüm bileşenleri içerir:

- **Glowroot Central**: Merkezi monitoring sunucusu
- **Web Arayüzü**: Performans metriklerini görüntüleme
- **Collector API**: Uygulamalardan veri toplama
- **Persistent Storage**: Veri kalıcılığı
- **Ingress**: Dış erişim
- **Security**: RBAC ve Network Policies

## ✨ Özellikler

### 🔧 Teknik Özellikler
- **Kubernetes Native**: Tam Kubernetes entegrasyonu
- **High Availability**: Otomatik ölçeklendirme (HPA)
- **Persistent Storage**: 10GB kalıcı depolama
- **Security**: RBAC, Network Policies, Service Account
- **Monitoring**: Liveness ve Readiness Probes
- **Ingress**: NGINX Ingress Controller desteği

### 📊 Monitoring Özellikleri
- **Transaction Monitoring**: HTTP isteklerinin performansı
- **Database Monitoring**: SQL sorgularının analizi
- **JVM Monitoring**: Heap, GC, Thread durumu
- **Custom Metrics**: Özel metrikler tanımlama
- **Alerting**: E-posta tabanlı uyarılar
- **Profiling**: Detaylı performans analizi

## 🔧 Gereksinimler

### Kubernetes Cluster
- Kubernetes 1.20+
- NGINX Ingress Controller
- Cert-Manager (opsiyonel, SSL için)
- Default Storage Class

### Araçlar
- `kubectl` (Kubernetes CLI)
- `helm` (opsiyonel)
- `bash` (deployment script için)

### Sistem Kaynakları
- **CPU**: Minimum 250m, Önerilen 500m
- **Memory**: Minimum 512Mi, Önerilen 1Gi
- **Storage**: 10GB persistent volume

## 🚀 Kurulum

### 1. Hızlı Kurulum (Script ile)

```bash
# Script'i çalıştırılabilir yap
chmod +x deploy-glowroot.sh

# Glowroot'u deploy et
./deploy-glowroot.sh
```

### 2. Manuel Kurulum

```bash
# YAML dosyasını uygula
kubectl apply -f glowroot-kubernetes-deployment.yaml

# Deployment durumunu kontrol et
kubectl get pods -n glowroot-apm
kubectl get services -n glowroot-apm
kubectl get ingress -n glowroot-apm
```

### 3. Helm ile Kurulum (Opsiyonel)

```bash
# Helm repository ekle
helm repo add glowroot https://glowroot.github.io/helm-charts
helm repo update

# Glowroot'u install et
helm install glowroot glowroot/glowroot-central \
  --namespace glowroot-apm \
  --create-namespace \
  --set persistence.enabled=true \
  --set ingress.enabled=true
```

## ⚙️ Konfigürasyon

### Environment Variables

| Değişken | Açıklama | Varsayılan |
|----------|----------|------------|
| `GLOWROOT_OPTS` | JVM options | `-Xms512m -Xmx1g -XX:+UseG1GC` |
| `JAVA_OPTS` | Java options | `-Djava.security.egd=file:/dev/./urandom` |

### ConfigMap Ayarları

Glowroot konfigürasyonu `glowroot-config` ConfigMap'inde tanımlanmıştır:

#### admin.json
```json
{
  "web": {
    "bindAddress": "0.0.0.0",
    "port": 4000,
    "contextPath": "/glowroot"
  },
  "storage": {
    "rollupExpirationHours": [
      {"captureTime": 0, "expirationHours": 4},
      {"captureTime": 4, "expirationHours": 24},
      {"captureTime": 24, "expirationHours": 24 * 7},
      {"captureTime": 24 * 7, "expirationHours": 24 * 30},
      {"captureTime": 24 * 30, "expirationHours": 24 * 90}
    ]
  }
}
```

#### collector.json
```json
{
  "transactions": {
    "slowThresholdMillis": 2000,
    "profilingIntervalMillis": 1000,
    "captureArgs": false,
    "captureResult": false
  },
  "profiles": {
    "slowThresholdMillis": 10000,
    "profilingIntervalMillis": 1000
  }
}
```

## 🌐 Kullanım

### Web Arayüzüne Erişim

1. **DNS Ayarları**: `glowroot.test.local` adresini Ingress IP'sine yönlendirin
2. **Tarayıcı**: `https://glowroot.test.local/glowroot` adresine gidin
3. **Varsayılan Kullanıcı**: İlk erişimde admin hesabı oluşturun

### API Erişimi

```bash
# Collector API
curl -X POST http://glowroot-collector.glowroot-apm.svc.cluster.local:8181/collector

# Web API
curl -X GET http://glowroot-web.glowroot-apm.svc.cluster.local:4000/glowroot/api
```

### Java Uygulamasına Agent Ekleme

```bash
# JVM parametresi olarak agent'ı ekleyin
java -javaagent:/path/to/glowroot.jar \
     -Dglowroot.collector.host=glowroot-collector.glowroot-apm.svc.cluster.local \
     -Dglowroot.collector.port=8181 \
     -jar your-application.jar
```

## 📈 Monitoring

### Pod Durumu

```bash
# Pod'ları listele
kubectl get pods -n glowroot-apm

# Pod loglarını görüntüle
kubectl logs -f deployment/glowroot -n glowroot-apm

# Pod'a bağlan
kubectl exec -it $(kubectl get pods -n glowroot-apm -l app=glowroot -o jsonpath='{.items[0].metadata.name}') -n glowroot-apm -- /bin/bash
```

### Service Durumu

```bash
# Service'leri listele
kubectl get services -n glowroot-apm

# Endpoint'leri kontrol et
kubectl get endpoints -n glowroot-apm
```

### Ingress Durumu

```bash
# Ingress'i listele
kubectl get ingress -n glowroot-apm

# Ingress detaylarını görüntüle
kubectl describe ingress glowroot-ingress -n glowroot-apm
```

### Resource Kullanımı

```bash
# Resource kullanımını izle
kubectl top pods -n glowroot-apm

# HPA durumunu kontrol et
kubectl get hpa -n glowroot-apm
```

## 🔧 Troubleshooting

### Yaygın Sorunlar

#### 1. Pod Başlatılamıyor
```bash
# Pod durumunu kontrol et
kubectl describe pod <pod-name> -n glowroot-apm

# Logları incele
kubectl logs <pod-name> -n glowroot-apm
```

#### 2. Ingress Çalışmıyor
```bash
# Ingress controller'ı kontrol et
kubectl get pods -n ingress-nginx

# Ingress events'lerini görüntüle
kubectl describe ingress glowroot-ingress -n glowroot-apm
```

#### 3. Persistent Volume Sorunu
```bash
# PVC durumunu kontrol et
kubectl get pvc -n glowroot-apm

# PV detaylarını görüntüle
kubectl describe pvc glowroot-data-pvc -n glowroot-apm
```

#### 4. Memory/CPU Sorunları
```bash
# Resource kullanımını izle
kubectl top pods -n glowroot-apm

# HPA durumunu kontrol et
kubectl describe hpa glowroot-hpa -n glowroot-apm
```

### Debug Komutları

```bash
# Tüm kaynakları listele
kubectl get all -n glowroot-apm

# ConfigMap'i kontrol et
kubectl get configmap glowroot-config -n glowroot-apm -o yaml

# Secret'ı kontrol et
kubectl get secret glowroot-tls -n glowroot-apm -o yaml

# Network policy'yi kontrol et
kubectl get networkpolicy -n glowroot-apm
```

## 🔒 Güvenlik

### RBAC (Role-Based Access Control)
- **ServiceAccount**: `glowroot-sa`
- **ClusterRole**: Sadece gerekli izinler
- **ClusterRoleBinding**: ServiceAccount ile ClusterRole bağlantısı

### Network Policies
- **Ingress**: Sadece HTTP/HTTPS trafiği
- **Egress**: DNS ve HTTP/HTTPS trafiği
- **Namespace Isolation**: Pod izolasyonu

### TLS/SSL
- **Cert-Manager**: Otomatik sertifika yönetimi
- **Let's Encrypt**: Ücretsiz SSL sertifikaları
- **Secret Management**: Güvenli sertifika saklama

## 📚 Ek Kaynaklar

### Glowroot Dokümantasyonu
- [Resmi Dokümantasyon](https://glowroot.org/docs/)
- [Agent Kurulumu](https://glowroot.org/docs/java-agent/)
- [API Referansı](https://glowroot.org/docs/api/)

### Kubernetes Kaynakları
- [Kubernetes Dokümantasyonu](https://kubernetes.io/docs/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Cert-Manager](https://cert-manager.io/docs/)

## 🤝 Katkıda Bulunma

1. Fork yapın
2. Feature branch oluşturun (`git checkout -b feature/amazing-feature`)
3. Commit yapın (`git commit -m 'Add amazing feature'`)
4. Push yapın (`git push origin feature/amazing-feature`)
5. Pull Request oluşturun

## 📄 Lisans

Bu proje MIT lisansı altında lisanslanmıştır. Detaylar için `LICENSE` dosyasına bakın.

## 📞 Destek

Sorunlarınız için:
- [GitHub Issues](https://github.com/your-repo/issues)
- [Glowroot Community](https://github.com/glowroot/glowroot/discussions)
- [Kubernetes Slack](https://slack.k8s.io/)

---

**Not**: Bu deployment test ortamı için tasarlanmıştır. Production ortamında ek güvenlik önlemleri alınması önerilir. 