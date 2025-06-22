#!/bin/bash

# Glowroot APM Rancher Deployment Script
# Bu script Rancher ortamında Glowroot'u deploy eder

set -euo pipefail

# Script konfigürasyonu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="glowroot-apm"
YAML_FILE="glowroot-kubernetes-deployment.yaml"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/tmp/glowroot_rancher_${TIMESTAMP}.log"

# Rancher özel ayarları
RANCHER_PROJECT_ID=""
RANCHER_CLUSTER_ID=""
RANCHER_API_TOKEN=""
RANCHER_URL=""

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
    rm -f /tmp/glowroot-*.tmp
}

trap cleanup EXIT

# Rancher konfigürasyonunu kontrol et
check_rancher_config() {
    log_info "Rancher konfigürasyonu kontrol ediliyor..."
    
    # Rancher URL kontrolü
    if [[ -z "$RANCHER_URL" ]]; then
        log_warning "RANCHER_URL tanımlanmamış. Varsayılan değer kullanılıyor..."
        RANCHER_URL="https://localhost"
    fi
    
    # Rancher API Token kontrolü
    if [[ -z "$RANCHER_API_TOKEN" ]]; then
        log_warning "RANCHER_API_TOKEN tanımlanmamış. kubectl kullanılacak..."
        return 0
    fi
    
    # Rancher CLI kontrolü
    if ! command -v rancher &> /dev/null; then
        log_warning "Rancher CLI bulunamadı. kubectl kullanılacak..."
        return 0
    fi
    
    log_success "Rancher konfigürasyonu hazır."
}

# Rancher cluster bilgilerini al
get_rancher_cluster_info() {
    log_info "Rancher cluster bilgileri alınıyor..."
    
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        # Rancher CLI ile cluster bilgilerini al
        rancher login --token "$RANCHER_API_TOKEN" "$RANCHER_URL" --skip-verify
        
        # Cluster listesini al
        log_info "Mevcut cluster'lar:"
        rancher cluster ls | tee -a "$LOG_FILE"
        
        # Project listesini al
        log_info "Mevcut project'ler:"
        rancher project ls | tee -a "$LOG_FILE"
    else
        # kubectl ile cluster bilgilerini al
        log_info "Cluster bilgileri (kubectl):"
        kubectl cluster-info | tee -a "$LOG_FILE"
        
        log_info "Node'lar:"
        kubectl get nodes -o wide | tee -a "$LOG_FILE"
    fi
}

# Rancher project/namespace oluştur
setup_rancher_namespace() {
    log_info "Rancher namespace/project kontrol ediliyor..."
    
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        # Rancher CLI ile namespace oluştur
        if ! rancher namespace ls | grep -q "$NAMESPACE"; then
            log_info "Rancher namespace oluşturuluyor: $NAMESPACE"
            rancher namespace create "$NAMESPACE"
            log_success "Namespace oluşturuldu."
        else
            log_info "Namespace zaten mevcut: $NAMESPACE"
        fi
    else
        # kubectl ile namespace oluştur
        if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
            log_info "Namespace oluşturuluyor: $NAMESPACE"
            kubectl create namespace "$NAMESPACE"
            log_success "Namespace oluşturuldu."
        else
            log_info "Namespace zaten mevcut: $NAMESPACE"
        fi
    fi
}

# Rancher'a özel YAML uygula
deploy_rancher_yaml() {
    log_info "Rancher YAML dosyası uygulanıyor..."
    
    if [[ ! -f "$YAML_FILE" ]]; then
        log_error "YAML dosyası bulunamadı: $YAML_FILE"
        exit 1
    fi
    
    # Rancher'a özel annotation'ları ekle
    log_info "Rancher annotation'ları ekleniyor..."
    
    # Geçici YAML dosyası oluştur
    TEMP_YAML="/tmp/glowroot-rancher-${TIMESTAMP}.yaml"
    
    # Rancher annotation'larını ekle
    sed 's/kind: Deployment/kind: Deployment\n  annotations:\n    field.cattle.io\/projectId: '"$RANCHER_PROJECT_ID"'/' "$YAML_FILE" > "$TEMP_YAML"
    
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        # Rancher CLI ile deploy et
        log_info "Rancher CLI ile deploy ediliyor..."
        rancher kubectl apply -f "$TEMP_YAML"
    else
        # kubectl ile deploy et
        log_info "kubectl ile deploy ediliyor..."
        kubectl apply -f "$TEMP_YAML"
    fi
    
    # Geçici dosyayı temizle
    rm -f "$TEMP_YAML"
    
    log_success "YAML dosyası uygulandı."
}

# Rancher monitoring
monitor_rancher_deployment() {
    log_info "Rancher deployment durumu izleniyor..."
    
    # Pod'ların hazır olmasını bekle
    log_info "Pod'ların hazır olması bekleniyor (maksimum 5 dakika)..."
    
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        rancher kubectl wait --for=condition=ready pod -l app=glowroot,component=app -n "$NAMESPACE" --timeout=300s
    else
        kubectl wait --for=condition=ready pod -l app=glowroot,component=app -n "$NAMESPACE" --timeout=300s
    fi
    
    # Service'leri kontrol et
    log_info "Service'ler kontrol ediliyor..."
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        rancher kubectl get services -n "$NAMESPACE" -o wide | tee -a "$LOG_FILE"
    else
        kubectl get services -n "$NAMESPACE" -o wide | tee -a "$LOG_FILE"
    fi
    
    # Ingress'i kontrol et
    log_info "Ingress kontrol ediliyor..."
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        rancher kubectl get ingress -n "$NAMESPACE" -o wide | tee -a "$LOG_FILE"
    else
        kubectl get ingress -n "$NAMESPACE" -o wide | tee -a "$LOG_FILE"
    fi
    
    log_success "Deployment başarıyla tamamlandı."
}

# Rancher erişim bilgileri
show_rancher_access_info() {
    log_info "=== RANCHER GLOWROOT ERİŞİM BİLGİLERİ ===" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    # Ingress IP'sini al
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        INGRESS_IP=$(rancher kubectl get ingress glowroot-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Bekleniyor...")
    else
        INGRESS_IP=$(kubectl get ingress glowroot-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Bekleniyor...")
    fi
    
    echo "=== Web Arayüzü ===" | tee -a "$LOG_FILE"
    echo "URL: https://glowroot.test.local/glowroot" | tee -a "$LOG_FILE"
    echo "Ingress IP: $INGRESS_IP" | tee -a "$LOG_FILE"
    echo "Namespace: $NAMESPACE" | tee -a "$LOG_FILE"
    echo "Rancher URL: $RANCHER_URL" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Rancher Komutları ===" | tee -a "$LOG_FILE"
    if command -v rancher &> /dev/null; then
        echo "Namespace'e git: rancher context switch $NAMESPACE" | tee -a "$LOG_FILE"
        echo "Pod'ları listele: rancher kubectl get pods -n $NAMESPACE" | tee -a "$LOG_FILE"
        echo "Logları görüntüle: rancher kubectl logs -f deployment/glowroot -n $NAMESPACE" | tee -a "$LOG_FILE"
    else
        echo "Pod'ları listele: kubectl get pods -n $NAMESPACE" | tee -a "$LOG_FILE"
        echo "Logları görüntüle: kubectl logs -f deployment/glowroot -n $NAMESPACE" | tee -a "$LOG_FILE"
    fi
    echo | tee -a "$LOG_FILE"
    
    echo "=== Rancher UI Erişimi ===" | tee -a "$LOG_FILE"
    echo "Rancher UI: $RANCHER_URL" | tee -a "$LOG_FILE"
    echo "Project: $NAMESPACE" | tee -a "$LOG_FILE"
    echo "Workload: glowroot" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "Log dosyası: $LOG_FILE" | tee -a "$LOG_FILE"
}

# Ana fonksiyon
main() {
    log_info "=== RANCHER GLOWROOT APM DEPLOYMENT BAŞLATILIYOR ==="
    log_info "Tarih: $(date)"
    log_info "Log dosyası: $LOG_FILE"
    echo
    
    check_rancher_config
    get_rancher_cluster_info
    setup_rancher_namespace
    deploy_rancher_yaml
    monitor_rancher_deployment
    show_rancher_access_info
    
    log_success "=== RANCHER GLOWROOT APM BAŞARIYLA DEPLOY EDİLDİ! ==="
    echo
    log_info "Rancher Özel Notlar:"
    log_info "1. Rancher UI'dan workload'ı takip edebilirsiniz"
    log_info "2. Rancher CLI ile yönetim yapabilirsiniz"
    log_info "3. Rancher monitoring entegrasyonu mevcut"
    log_info "4. Detaylı loglar: $LOG_FILE"
}

# Script'i çalıştır
main "$@" 