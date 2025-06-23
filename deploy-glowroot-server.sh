#!/bin/bash

# Glowroot APM Server Deployment Script (Cassandra Destekli)
# Bu script sunucuda direkt çalıştırılır ve Glowroot'u Kubernetes'e deploy eder

set -euo pipefail

# Script konfigürasyonu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="glowroot-apm"
YAML_FILE="glowroot-kubernetes-deployment-fixed.yaml"
CASSANDRA_YAML="cassandra-deployment.yaml"
STORAGE_YAML="k3s-storage-class.yaml"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/tmp/glowroot_deploy_${TIMESTAMP}.log"

# Renk kodları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log fonksiyonları
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Hata yönetimi
cleanup() {
    log_info "Temizlik işlemleri yapılıyor..."
    # Geçici dosyaları temizle
    rm -f /tmp/glowroot-*.tmp
}

trap cleanup EXIT

# Sistem bilgilerini kontrol et
check_system_info() {
    log_info "Sistem bilgileri kontrol ediliyor..."
    
    # OS bilgisi
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        log_info "OS: $PRETTY_NAME"
    else
        log_info "OS: $(uname -s)"
    fi
    
    # Kernel versiyonu
    log_info "Kernel: $(uname -r)"
    
    # CPU bilgisi
    log_info "CPU: $(nproc) core"
    
    # Memory bilgisi
    MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
    log_info "Memory: ${MEMORY_GB}GB"
    
    # Disk bilgisi
    DISK_GB=$(df -BG / | awk 'NR==2{print $2}' | sed 's/G//')
    log_info "Disk: ${DISK_GB}GB available"
}

# Gerekli araçları kontrol et
check_prerequisites() {
    log_info "Gerekli araçlar kontrol ediliyor..."
    
    # kubectl kontrolü
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl bulunamadı. Yükleniyor..."
        
        # kubectl yükleme
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            chmod +x kubectl
            sudo mv kubectl /usr/local/bin/
        else
            log_error "kubectl otomatik yükleme desteklenmiyor. Manuel yükleyin."
            exit 1
        fi
    else
        log_success "kubectl mevcut: $(kubectl version --client --short)"
    fi
    
    # Kubernetes cluster bağlantısını kontrol et
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Kubernetes cluster'ına bağlanılamıyor."
        log_info "Cluster bağlantısını kontrol edin:"
        log_info "1. kubeconfig dosyasının doğru konumda olduğunu kontrol edin"
        log_info "2. Cluster'ın çalışır durumda olduğunu kontrol edin"
        exit 1
    fi
    
    # Cluster bilgilerini göster
    log_info "Cluster bilgileri:"
    kubectl cluster-info | tee -a "$LOG_FILE"
    
    # Node'ları listele
    log_info "Cluster node'ları:"
    kubectl get nodes -o wide | tee -a "$LOG_FILE"
    
    log_success "Gerekli araçlar kontrol edildi."
}

# Namespace kontrolü ve oluşturma
setup_namespace() {
    log_info "Namespace kontrol ediliyor..."
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_warning "Namespace '$NAMESPACE' zaten mevcut."
        read -p "Devam etmek istiyor musunuz? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment iptal edildi."
            exit 0
        fi
    else
        log_info "Namespace '$NAMESPACE' oluşturuluyor..."
        kubectl create namespace "$NAMESPACE"
        log_success "Namespace oluşturuldu."
    fi
}

# Storage class kurulumu
setup_storage() {
    log_info "Storage class kurulumu kontrol ediliyor..."
    
    if [[ -f "$STORAGE_YAML" ]]; then
        log_info "K3s storage class uygulanıyor..."
        kubectl apply -f "$STORAGE_YAML"
        log_success "Storage class uygulandı."
    else
        log_warning "Storage class YAML dosyası bulunamadı: $STORAGE_YAML"
        log_info "Varsayılan storage class kullanılacak."
    fi
}

# Cassandra deployment
deploy_cassandra() {
    log_info "Cassandra deployment kontrol ediliyor..."
    
    if [[ ! -f "$CASSANDRA_YAML" ]]; then
        log_error "Cassandra YAML dosyası bulunamadı: $CASSANDRA_YAML"
        exit 1
    fi
    
    # Mevcut Cassandra deployment'ını kontrol et
    if kubectl get deployment cassandra -n "$NAMESPACE" &> /dev/null; then
        log_warning "Cassandra deployment zaten mevcut."
        read -p "Cassandra'yı yeniden deploy etmek istiyor musunuz? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Mevcut Cassandra deployment siliniyor..."
            kubectl delete deployment cassandra -n "$NAMESPACE" --ignore-not-found=true
            kubectl delete pvc cassandra-data-pvc -n "$NAMESPACE" --ignore-not-found=true
        else
            log_info "Mevcut Cassandra deployment kullanılacak."
            return 0
        fi
    fi
    
    # Cassandra YAML syntax kontrolü
    log_info "Cassandra YAML syntax kontrol ediliyor..."
    if ! kubectl apply --dry-run=client -f "$CASSANDRA_YAML" &> /dev/null; then
        log_error "Cassandra YAML dosyasında syntax hatası var."
        exit 1
    fi
    
    log_success "Cassandra YAML dosyası doğrulandı."
    
    # Cassandra'yı deploy et
    log_info "Cassandra deploy ediliyor..."
    kubectl apply -f "$CASSANDRA_YAML"
    
    # Cassandra'nın hazır olmasını bekle
    log_info "Cassandra'nın hazır olması bekleniyor (maksimum 10 dakika)..."
    if kubectl wait --for=condition=ready pod -l app=cassandra -n "$NAMESPACE" --timeout=600s; then
        log_success "Cassandra hazır."
    else
        log_error "Cassandra hazır olmadı. Logları kontrol edin."
        kubectl get pods -n "$NAMESPACE" -l app=cassandra
        kubectl describe pods -l app=cassandra -n "$NAMESPACE"
        exit 1
    fi
    
    # Cassandra'nın tamamen başlamasını bekle
    log_info "Cassandra servisinin tamamen başlaması bekleniyor..."
    sleep 30
    
    # Cassandra keyspace'ini oluştur
    log_info "Cassandra keyspace oluşturuluyor..."
    kubectl exec -n "$NAMESPACE" deployment/cassandra -- cqlsh -e "CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};" || {
        log_warning "Keyspace oluşturulamadı, Cassandra henüz tam hazır olmayabilir."
        log_info "Keyspace'i manuel olarak oluşturabilirsiniz:"
        log_info "kubectl exec -n $NAMESPACE deployment/cassandra -- cqlsh -e \"CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};\""
    }
    
    log_success "Cassandra deployment tamamlandı."
}

# YAML dosyasını kontrol et ve uygula
deploy_yaml() {
    log_info "Glowroot YAML dosyası kontrol ediliyor..."
    
    if [[ ! -f "$YAML_FILE" ]]; then
        log_error "Glowroot YAML dosyası bulunamadı: $YAML_FILE"
        exit 1
    fi
    
    # Mevcut Glowroot deployment'ını kontrol et
    if kubectl get deployment glowroot -n "$NAMESPACE" &> /dev/null; then
        log_warning "Glowroot deployment zaten mevcut."
        read -p "Glowroot'u yeniden deploy etmek istiyor musunuz? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Mevcut Glowroot deployment siliniyor..."
            kubectl delete deployment glowroot -n "$NAMESPACE" --ignore-not-found=true
            kubectl delete pvc glowroot-data-pvc -n "$NAMESPACE" --ignore-not-found=true
        else
            log_info "Mevcut Glowroot deployment kullanılacak."
            return 0
        fi
    fi
    
    # YAML syntax kontrolü
    log_info "Glowroot YAML syntax kontrol ediliyor..."
    if ! kubectl apply --dry-run=client -f "$YAML_FILE" &> /dev/null; then
        log_error "Glowroot YAML dosyasında syntax hatası var."
        exit 1
    fi
    
    log_success "Glowroot YAML dosyası doğrulandı."
    
    # YAML dosyasını uygula
    log_info "Glowroot APM deploy ediliyor..."
    kubectl apply -f "$YAML_FILE"
    
    log_success "Glowroot APM deployment başlatıldı."
}

# Deployment durumunu kontrol et
monitor_deployment() {
    log_info "Deployment durumu izleniyor..."
    
    # Pod'ların hazır olmasını bekle
    log_info "Pod'ların hazır olması bekleniyor (maksimum 5 dakika)..."
    if kubectl wait --for=condition=ready pod -l app=glowroot,component=app -n "$NAMESPACE" --timeout=300s; then
        log_success "Glowroot pod'ları hazır."
    else
        log_error "Glowroot pod'ları hazır olmadı. Logları kontrol edin."
        kubectl get pods -n "$NAMESPACE"
        kubectl describe pods -l app=glowroot -n "$NAMESPACE"
        exit 1
    fi
    
    # Service'lerin oluşturulmasını kontrol et
    log_info "Service'ler kontrol ediliyor..."
    kubectl get services -n "$NAMESPACE" -o wide | tee -a "$LOG_FILE"
    
    # Ingress'in oluşturulmasını kontrol et
    log_info "Ingress kontrol ediliyor..."
    kubectl get ingress -n "$NAMESPACE" -o wide | tee -a "$LOG_FILE"
    
    # Persistent Volume kontrolü
    log_info "Persistent Volume kontrol ediliyor..."
    kubectl get pvc -n "$NAMESPACE" | tee -a "$LOG_FILE"
    
    log_success "Deployment başarıyla tamamlandı."
}

# Erişim bilgilerini göster
show_access_info() {
    log_info "=== GLOWROOT ERİŞİM BİLGİLERİ ===" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    # Ingress IP'sini al
    INGRESS_IP=$(kubectl get ingress glowroot-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Bekleniyor...")
    
    echo "=== Web Arayüzü ===" | tee -a "$LOG_FILE"
    echo "URL: http://glowroot.test.local" | tee -a "$LOG_FILE"
    echo "Ingress IP: $INGRESS_IP" | tee -a "$LOG_FILE"
    echo "Namespace: $NAMESPACE" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Service Endpoints ===" | tee -a "$LOG_FILE"
    kubectl get services -n "$NAMESPACE" -o wide | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Pod Durumu ===" | tee -a "$LOG_FILE"
    kubectl get pods -n "$NAMESPACE" -o wide | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Kullanışlı Komutlar ===" | tee -a "$LOG_FILE"
    echo "Glowroot logları:" | tee -a "$LOG_FILE"
    echo "kubectl logs -f deployment/glowroot -n $NAMESPACE" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Cassandra logları:" | tee -a "$LOG_FILE"
    echo "kubectl logs -f deployment/cassandra -n $NAMESPACE" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Glowroot pod'una bağlanma:" | tee -a "$LOG_FILE"
    echo "kubectl exec -it \$(kubectl get pods -n $NAMESPACE -l app=glowroot -o jsonpath='{.items[0].metadata.name}') -n $NAMESPACE -- /bin/bash" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Cassandra pod'una bağlanma:" | tee -a "$LOG_FILE"
    echo "kubectl exec -it \$(kubectl get pods -n $NAMESPACE -l app=cassandra -o jsonpath='{.items[0].metadata.name}') -n $NAMESPACE -- cqlsh" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Resource kullanımı:" | tee -a "$LOG_FILE"
    echo "kubectl top pods -n $NAMESPACE" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== DNS Ayarları ===" | tee -a "$LOG_FILE"
    echo "glowroot.test.local adresini $INGRESS_IP IP'sine yönlendirin" | tee -a "$LOG_FILE"
    echo "Örnek: echo '$INGRESS_IP glowroot.test.local' >> /etc/hosts" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "Log dosyası: $LOG_FILE" | tee -a "$LOG_FILE"
}

# Health check
health_check() {
    log_info "Health check yapılıyor..."
    
    # Cassandra pod'larının çalışır durumda olduğunu kontrol et
    CASSANDRA_RUNNING=$(kubectl get pods -n "$NAMESPACE" -l app=cassandra --field-selector=status.phase=Running --no-headers | wc -l)
    CASSANDRA_TOTAL=$(kubectl get pods -n "$NAMESPACE" -l app=cassandra --no-headers | wc -l)
    
    if [[ "$CASSANDRA_RUNNING" -eq "$CASSANDRA_TOTAL" && "$CASSANDRA_TOTAL" -gt 0 ]]; then
        log_success "Cassandra pod'ları çalışıyor ($CASSANDRA_RUNNING/$CASSANDRA_TOTAL)"
    else
        log_warning "Cassandra pod'ları çalışmıyor ($CASSANDRA_RUNNING/$CASSANDRA_TOTAL)"
    fi
    
    # Glowroot pod'larının çalışır durumda olduğunu kontrol et
    GLOWROOT_RUNNING=$(kubectl get pods -n "$NAMESPACE" -l app=glowroot --field-selector=status.phase=Running --no-headers | wc -l)
    GLOWROOT_TOTAL=$(kubectl get pods -n "$NAMESPACE" -l app=glowroot --no-headers | wc -l)
    
    if [[ "$GLOWROOT_RUNNING" -eq "$GLOWROOT_TOTAL" && "$GLOWROOT_TOTAL" -gt 0 ]]; then
        log_success "Glowroot pod'ları çalışıyor ($GLOWROOT_RUNNING/$GLOWROOT_TOTAL)"
    else
        log_warning "Glowroot pod'ları çalışmıyor ($GLOWROOT_RUNNING/$GLOWROOT_TOTAL)"
    fi
    
    # Service'lerin endpoint'lerini kontrol et
    kubectl get endpoints -n "$NAMESPACE" | tee -a "$LOG_FILE"
}

# Ana fonksiyon
main() {
    log_info "=== GLOWROOT APM SERVER DEPLOYMENT BAŞLATILIYOR (CASSANDRA DESTEKLİ) ==="
    log_info "Tarih: $(date)"
    log_info "Log dosyası: $LOG_FILE"
    echo
    
    check_system_info
    check_prerequisites
    setup_namespace
    setup_storage
    deploy_cassandra
    deploy_yaml
    monitor_deployment
    health_check
    show_access_info
    
    log_success "=== GLOWROOT APM BAŞARIYLA DEPLOY EDİLDİ! ==="
    echo
    log_info "Önemli Notlar:"
    log_info "1. DNS ayarlarınızı yapılandırmayı unutmayın"
    log_info "2. Firewall ayarlarını kontrol edin"
    log_info "3. Cassandra ve Glowroot birlikte çalışıyor"
    log_info "4. Detaylı loglar: $LOG_FILE"
    log_info "5. Cassandra keyspace'i otomatik oluşturuldu"
}

# Script'i çalıştır
main "$@" 