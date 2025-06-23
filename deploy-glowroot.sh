#!/bin/bash

# Glowroot APM Kubernetes Deployment Script (Cassandra Destekli)
# Bu script Glowroot APM'i Kubernetes test ortamına deploy eder

set -euo pipefail

# Script konfigürasyonu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="glowroot-apm"
YAML_FILE="glowroot-kubernetes-deployment-fixed.yaml"
CASSANDRA_YAML="cassandra-deployment.yaml"
STORAGE_YAML="k3s-storage-class.yaml"

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
        # Sadece storage class'ı uygula, PVC'yi sonra uygula
        kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF
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

# YAML dosyasını kontrol et
validate_yaml() {
    log_info "Glowroot YAML dosyası doğrulanıyor..."
    
    if [[ ! -f "$YAML_FILE" ]]; then
        log_error "Glowroot YAML dosyası bulunamadı: $YAML_FILE"
        exit 1
    fi
    
    # YAML syntax kontrolü
    if ! kubectl apply --dry-run=client -f "$YAML_FILE" &> /dev/null; then
        log_error "Glowroot YAML dosyasında syntax hatası var."
        exit 1
    fi
    
    log_success "Glowroot YAML dosyası doğrulandı."
}

# Glowroot'u deploy et
deploy_glowroot() {
    log_info "Glowroot APM deploy ediliyor..."
    
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
    
    # YAML dosyasını uygula
    kubectl apply -f "$YAML_FILE"
    
    log_success "Glowroot APM deployment başlatıldı."
}

# Deployment durumunu kontrol et
check_deployment_status() {
    log_info "Deployment durumu kontrol ediliyor..."
    
    # Cassandra pod'larının hazır olmasını bekle
    log_info "Cassandra pod'larının hazır olması bekleniyor..."
    kubectl wait --for=condition=ready pod -l app=cassandra -n "$NAMESPACE" --timeout=300s
    
    # Glowroot pod'larının hazır olmasını bekle
    log_info "Glowroot pod'larının hazır olması bekleniyor..."
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
    echo "URL: http://glowroot.test.local"
    echo "Namespace: $NAMESPACE"
    echo
    echo "=== Service Endpoints ==="
    kubectl get services -n "$NAMESPACE" -o wide
    echo
    echo "=== Pod Durumu ==="
    kubectl get pods -n "$NAMESPACE" -o wide
    echo
    echo "=== Logları Görüntüleme ==="
    echo "Glowroot logları: kubectl logs -f deployment/glowroot -n $NAMESPACE"
    echo "Cassandra logları: kubectl logs -f deployment/cassandra -n $NAMESPACE"
    echo
    echo "=== Pod'a Bağlanma ==="
    echo "Glowroot: kubectl exec -it \$(kubectl get pods -n $NAMESPACE -l app=glowroot -o jsonpath='{.items[0].metadata.name}') -n $NAMESPACE -- /bin/bash"
    echo "Cassandra: kubectl exec -it \$(kubectl get pods -n $NAMESPACE -l app=cassandra -o jsonpath='{.items[0].metadata.name}') -n $NAMESPACE -- cqlsh"
    echo
    echo "=== Resource Kullanımı ==="
    echo "kubectl top pods -n $NAMESPACE"
}

# Ana fonksiyon
main() {
    log_info "Glowroot APM Kubernetes Deployment başlatılıyor (Cassandra Destekli)..."
    echo
    
    check_prerequisites
    check_namespace
    setup_storage
    deploy_cassandra
    validate_yaml
    deploy_glowroot
    check_deployment_status
    show_access_info
    
    log_success "Glowroot APM başarıyla deploy edildi!"
    echo
    log_info "Not: DNS ayarlarınızı yapılandırmayı unutmayın (glowroot.test.local -> Ingress IP)"
    log_info "Not: Cassandra ve Glowroot birlikte çalışıyor"
}

# Script'i çalıştır
main "$@" 