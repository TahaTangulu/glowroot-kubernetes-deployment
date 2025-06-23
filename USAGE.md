# Glowroot APM Deployment Kullanım Kılavuzu

Bu kılavuz, Glowroot APM'i farklı ortamlarda nasıl deploy edeceğinizi açıklar.

## 📁 Dosya Yapısı

```
.
├── glowroot-kubernetes-deployment.yaml  # Kubernetes YAML dosyası
├── deploy-glowroot.sh                   # Genel deployment script'i
├── deploy-glowroot-server.sh            # Sunucu için Kubernetes script'i
├── deploy-glowroot-docker.sh            # Docker için script'i
├── README.md                            # Detaylı dokümantasyon
├── USAGE.md                             # Bu kullanım kılavuzu
└── docker-compose.yml                   # Docker Compose dosyası (otomatik oluşturulur)
```

## 🚀 Hızlı Başlangıç

### 1. Kubernetes Ortamında (Sunucu)

```bash
# Script'i çalıştırılabilir yap
chmod +x deploy-glowroot-server.sh

# Glowroot'u deploy et
./deploy-glowroot-server.sh
```

### 2. Docker Ortamında

```bash
# Script'i çalıştırılabilir yap
chmod +x deploy-glowroot-docker.sh

# Glowroot'u deploy et
./deploy-glowroot-docker.sh
```

## 🔧 Detaylı Kullanım

### Kubernetes Deployment (Sunucu)

#### Gereksinimler
- Kubernetes cluster (1.20+)
- kubectl CLI
- NGINX Ingress Controller
- Default Storage Class

#### Adımlar

1. **Script'i hazırla:**
   ```bash
   chmod +x deploy-glowroot-server.sh
   ```

2. **Deploy et:**
   ```bash
   ./deploy-glowroot-server.sh
   ```

3. **Erişim:**
   - Web Arayüzü: `https://glowroot.test.local/glowroot`
   - DNS ayarlarını yapılandırın

#### Özellikler
- ✅ Otomatik kubectl yükleme
- ✅ Sistem bilgileri kontrolü
- ✅ Cluster bağlantı kontrolü
- ✅ Namespace yönetimi
- ✅ Deployment monitoring
- ✅ Health check
- ✅ Detaylı loglama
- ✅ Erişim bilgileri

### Docker Deployment

#### Gereksinimler
- Docker
- Docker Compose (opsiyonel)
- 5GB+ disk alanı

#### Adımlar

1. **Script'i hazırla:**
   ```bash
   chmod +x deploy-glowroot-docker.sh
   ```

2. **Deploy et:**
   ```bash
   ./deploy-glowroot-docker.sh
   ```

3. **Erişim:**
   - Web Arayüzü: `http://localhost:4000/glowroot`
   - Collector API: `http://localhost:8181`

#### Özellikler
- ✅ Docker servis kontrolü
- ✅ Otomatik image çekme
- ✅ Network ve volume yönetimi
- ✅ Container monitoring
- ✅ Health check
- ✅ Docker Compose dosyası oluşturma
- ✅ Detaylı loglama

## 📊 Monitoring ve Yönetim

### Kubernetes Komutları

```bash
# Pod durumu
kubectl get pods -n glowroot-apm

# Logları görüntüle
kubectl logs -f deployment/glowroot -n glowroot-apm

# Pod'a bağlan
kubectl exec -it $(kubectl get pods -n glowroot-apm -l app=glowroot -o jsonpath='{.items[0].metadata.name}') -n glowroot-apm -- /bin/bash

# Resource kullanımı
kubectl top pods -n glowroot-apm

# Service'leri listele
kubectl get services -n glowroot-apm

# Ingress durumu
kubectl get ingress -n glowroot-apm
```

### Docker Komutları

```bash
# Container durumu
docker ps | grep glowroot

# Logları görüntüle
docker logs -f glowroot-apm

# Container'a bağlan
docker exec -it glowroot-apm /bin/bash

# Container durdur/başlat
docker stop glowroot-apm
docker start glowroot-apm

# Container sil
docker rm -f glowroot-apm

# Volume'ları listele
docker volume ls | grep glowroot
```

## 🔧 Konfigürasyon

### Environment Variables

#### Kubernetes
```yaml
env:
- name: GLOWROOT_OPTS
  value: "-Xms512m -Xmx1g -XX:+UseG1GC"
- name: JAVA_OPTS
  value: "-Djava.security.egd=file:/dev/./urandom"
```

#### Docker
```bash
-e GLOWROOT_OPTS="-Xms512m -Xmx1g -XX:+UseG1GC"
-e JAVA_OPTS="-Djava.security.egd=file:/dev/./urandom"
```

### Port Konfigürasyonu

| Ortam | Web Port | Collector Port |
|-------|----------|----------------|
| Kubernetes | 4000 (ClusterIP) | 8181 (ClusterIP) |
| Docker | 4000 (Host) | 8181 (Host) |

## 🚨 Troubleshooting

### Yaygın Sorunlar

#### 1. Kubernetes - Pod Başlatılamıyor
```bash
# Pod durumunu kontrol et
kubectl describe pod <pod-name> -n glowroot-apm

# Logları incele
kubectl logs <pod-name> -n glowroot-apm

# Resource kullanımını kontrol et
kubectl top nodes
```

#### 2. Kubernetes - Ingress Çalışmıyor
```bash
# Ingress controller'ı kontrol et
kubectl get pods -n ingress-nginx

# Ingress events'lerini görüntüle
kubectl describe ingress glowroot-ingress -n glowroot-apm

# DNS ayarlarını kontrol et
nslookup glowroot.test.local
```

#### 3. Docker - Container Başlatılamıyor
```bash
# Docker servisini kontrol et
sudo systemctl status docker

# Disk alanını kontrol et
df -h

# Container loglarını incele
docker logs glowroot-apm

# Port çakışmasını kontrol et
netstat -tlnp | grep :4000
netstat -tlnp | grep :8181
```

#### 4. Docker - Port Erişim Sorunu
```bash
# Firewall ayarlarını kontrol et
sudo ufw status

# Port'ları aç
sudo ufw allow 4000
sudo ufw allow 8181

# Container IP'sini kontrol et
docker inspect glowroot-apm | grep IPAddress
```

### Debug Komutları

#### Kubernetes
```bash
# Tüm kaynakları listele
kubectl get all -n glowroot-apm

# ConfigMap'i kontrol et
kubectl get configmap glowroot-config -n glowroot-apm -o yaml

# Events'leri görüntüle
kubectl get events -n glowroot-apm --sort-by='.lastTimestamp'
```

#### Docker
```bash
# Container detaylarını görüntüle
docker inspect glowroot-apm

# Network bilgilerini kontrol et
docker network ls
docker network inspect glowroot-network

# Volume bilgilerini kontrol et
docker volume inspect glowroot-data
```

## 🔒 Güvenlik

### Kubernetes
- RBAC (Role-Based Access Control)
- Network Policies
- TLS/SSL sertifikaları
- Namespace izolasyonu

### Docker
- Container izolasyonu
- Volume güvenliği
- Network izolasyonu
- Resource limitleri

## 📈 Performans Optimizasyonu

### Kubernetes
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

### Docker
```bash
# Memory limiti
docker run --memory=1g ...

# CPU limiti
docker run --cpus=0.5 ...
```

## 🔄 Backup ve Restore

### Kubernetes
```bash
# ConfigMap backup
kubectl get configmap glowroot-config -n glowroot-apm -o yaml > backup-configmap.yaml

# PVC backup (veri)
kubectl get pvc glowroot-data-pvc -n glowroot-apm -o yaml > backup-pvc.yaml
```

### Docker
```bash
# Volume backup
docker run --rm -v glowroot-data:/data -v $(pwd):/backup alpine tar czf /backup/glowroot-backup.tar.gz -C /data .

# Volume restore
docker run --rm -v glowroot-data:/data -v $(pwd):/backup alpine tar xzf /backup/glowroot-backup.tar.gz -C /data
```

## 📞 Destek

Sorunlarınız için:
1. Log dosyalarını kontrol edin: `/tmp/glowroot_*.log`
2. Script çıktılarını inceleyin
3. Kubernetes/Docker komutlarını manuel çalıştırın
4. Sistem kaynaklarını kontrol edin

---

**Not**: Bu script'ler test ortamı için tasarlanmıştır. Production ortamında ek güvenlik önlemleri alınması önerilir. 