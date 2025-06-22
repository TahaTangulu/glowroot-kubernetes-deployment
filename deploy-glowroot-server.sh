#!/bin/bash

# Glowroot APM Server Deployment Script
# Bu script sunucuda direkt çalıştırılır ve Glowroot'u Kubernetes'e deploy eder

set -euo pipefail

# Script konfigürasyonu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="glowroot-apm"
YAML_FILE="glowroot-kubernetes-deployment.yaml"
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

# YAML dosyasını kontrol et ve uygula
deploy_yaml() {
    log_info "YAML dosyası kontrol ediliyor..."
    
    if [[ ! -f "$YAML_FILE" ]]; then
        log_error "YAML dosyası bulunamadı: $YAML_FILE"
        exit 1
    fi
    
    # YAML syntax kontrolü
    log_info "YAML syntax kontrol ediliyor..."
    if ! kubectl apply --dry-run=client -f "$YAML_FILE" &> /dev/null; then
        log_error "YAML dosyasında syntax hatası var."
        exit 1
    fi
    
    log_success "YAML dosyası doğrulandı."
    
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
        log_success "Pod'lar hazır."
    else
        log_error "Pod'lar hazır olmadı. Logları kontrol edin."
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
    echo "URL: https://glowroot.test.local/glowroot" | tee -a "$LOG_FILE"
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
    echo "Logları görüntüleme:" | tee -a "$LOG_FILE"
    echo "kubectl logs -f deployment/glowroot -n $NAMESPACE" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Pod'a bağlanma:" | tee -a "$LOG_FILE"
    echo "kubectl exec -it \$(kubectl get pods -n $NAMESPACE -l app=glowroot -o jsonpath='{.items[0].metadata.name}') -n $NAMESPACE -- /bin/bash" | tee -a "$LOG_FILE"
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
    
    # Pod'ların çalışır durumda olduğunu kontrol et
    RUNNING_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=glowroot --field-selector=status.phase=Running --no-headers | wc -l)
    TOTAL_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=glowroot --no-headers | wc -l)
    
    if [[ "$RUNNING_PODS" -eq "$TOTAL_PODS" && "$TOTAL_PODS" -gt 0 ]]; then
        log_success "Tüm pod'lar çalışıyor ($RUNNING_PODS/$TOTAL_PODS)"
    else
        log_warning "Bazı pod'lar çalışmıyor ($RUNNING_PODS/$TOTAL_PODS)"
    fi
    
    # Service'lerin endpoint'lerini kontrol et
    kubectl get endpoints -n "$NAMESPACE" | tee -a "$LOG_FILE"
}

# Ana fonksiyon
main() {
    log_info "=== GLOWROOT APM SERVER DEPLOYMENT BAŞLATILIYOR ==="
    log_info "Tarih: $(date)"
    log_info "Log dosyası: $LOG_FILE"
    echo
    
    check_system_info
    check_prerequisites
    setup_namespace
    deploy_yaml
    monitor_deployment
    health_check
    show_access_info
    
    log_success "=== GLOWROOT APM BAŞARIYLA DEPLOY EDİLDİ! ==="
    echo
    log_info "Önemli Notlar:"
    log_info "1. DNS ayarlarınızı yapılandırmayı unutmayın"
    log_info "2. Firewall ayarlarını kontrol edin"
    log_info "3. SSL sertifikası için cert-manager kurulu olmalı"
    log_info "4. Detaylı loglar: $LOG_FILE"
}

# Script'i çalıştır
main "$@" 