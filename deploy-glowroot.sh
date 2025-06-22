#!/bin/bash

# Glowroot APM Kubernetes Deployment Script
# Bu script Glowroot APM'i Kubernetes test ortamına deploy eder

set -euo pipefail

# Script konfigürasyonu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="glowroot-apm"
YAML_FILE="glowroot-kubernetes-deployment.yaml"

# Renk kodları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log fonksiyonları
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Hata yönetimi
cleanup() {
    log_info "Temizlik işlemleri yapılıyor..."
    # Geçici dosyaları temizle
    rm -f /tmp/glowroot-*.tmp
}

trap cleanup EXIT

# Gerekli araçları kontrol et
check_prerequisites() {
    log_info "Gerekli araçlar kontrol ediliyor..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl bulunamadı. Lütfen Kubernetes CLI'ı yükleyin."
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        log_warning "Helm bulunamadı. Bazı özellikler kullanılamayabilir."
    fi
    
    # Kubernetes cluster bağlantısını kontrol et
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Kubernetes cluster'ına bağlanılamıyor."
        exit 1
    fi
    
    log_success "Gerekli araçlar kontrol edildi."
}

# Namespace kontrolü
check_namespace() {
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
        log_info "Namespace '$NAMESPACE' oluşturulacak."
    fi
}

# YAML dosyasını kontrol et
validate_yaml() {
    log_info "YAML dosyası doğrulanıyor..."
    
    if [[ ! -f "$YAML_FILE" ]]; then
        log_error "YAML dosyası bulunamadı: $YAML_FILE"
        exit 1
    fi
    
    # YAML syntax kontrolü
    if ! kubectl apply --dry-run=client -f "$YAML_FILE" &> /dev/null; then
        log_error "YAML dosyasında syntax hatası var."
        exit 1
    fi
    
    log_success "YAML dosyası doğrulandı."
}

# Glowroot'u deploy et
deploy_glowroot() {
    log_info "Glowroot APM deploy ediliyor..."
    
    # YAML dosyasını uygula
    kubectl apply -f "$YAML_FILE"
    
    log_success "Glowroot APM deployment başlatıldı."
}

# Deployment durumunu kontrol et
check_deployment_status() {
    log_info "Deployment durumu kontrol ediliyor..."
    
    # Pod'ların hazır olmasını bekle
    log_info "Pod'ların hazır olması bekleniyor..."
    kubectl wait --for=condition=ready pod -l app=glowroot,component=app -n "$NAMESPACE" --timeout=300s
    
    # Service'lerin oluşturulmasını bekle
    log_info "Service'ler kontrol ediliyor..."
    kubectl get services -n "$NAMESPACE"
    
    # Ingress'in oluşturulmasını bekle
    log_info "Ingress kontrol ediliyor..."
    kubectl get ingress -n "$NAMESPACE"
    
    log_success "Deployment başarıyla tamamlandı."
}

# Erişim bilgilerini göster
show_access_info() {
    log_info "Erişim bilgileri:"
    echo
    echo "=== Glowroot Web Arayüzü ==="
    echo "URL: https://glowroot.test.local/glowroot"
    echo "Namespace: $NAMESPACE"
    echo
    echo "=== Service Endpoints ==="
    kubectl get services -n "$NAMESPACE" -o wide
    echo
    echo "=== Pod Durumu ==="
    kubectl get pods -n "$NAMESPACE" -o wide
    echo
    echo "=== Logları Görüntüleme ==="
    echo "kubectl logs -f deployment/glowroot -n $NAMESPACE"
    echo
    echo "=== Pod'a Bağlanma ==="
    echo "kubectl exec -it \$(kubectl get pods -n $NAMESPACE -l app=glowroot -o jsonpath='{.items[0].metadata.name}') -n $NAMESPACE -- /bin/bash"
}

# Ana fonksiyon
main() {
    log_info "Glowroot APM Kubernetes Deployment başlatılıyor..."
    echo
    
    check_prerequisites
    check_namespace
    validate_yaml
    deploy_glowroot
    check_deployment_status
    show_access_info
    
    log_success "Glowroot APM başarıyla deploy edildi!"
    echo
    log_info "Not: DNS ayarlarınızı yapılandırmayı unutmayın (glowroot.test.local -> Ingress IP)"
}

# Script'i çalıştır
main "$@" 