#!/bin/bash

# Glowroot APM Rancher Deployment Script (Cassandra Destekli)
# Bu script Rancher ortamında Glowroot'u deploy eder

set -euo pipefail

# Script konfigürasyonu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="glowroot-apm"
YAML_FILE="glowroot-kubernetes-deployment-fixed.yaml"
CASSANDRA_YAML="cassandra-deployment.yaml"
STORAGE_YAML="k3s-storage-class.yaml"
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

# Storage class kurulumu
setup_storage() {
    log_info "Storage class kurulumu kontrol ediliyor..."
    
    if [[ -f "$STORAGE_YAML" ]]; then
        log_info "K3s storage class uygulanıyor..."
        if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
            rancher kubectl apply -f "$STORAGE_YAML"
        else
            kubectl apply -f "$STORAGE_YAML"
        fi
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
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        if rancher kubectl get deployment cassandra -n "$NAMESPACE" &> /dev/null; then
            log_warning "Cassandra deployment zaten mevcut."
            read -p "Cassandra'yı yeniden deploy etmek istiyor musunuz? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Mevcut Cassandra deployment siliniyor..."
                rancher kubectl delete deployment cassandra -n "$NAMESPACE" --ignore-not-found=true
                rancher kubectl delete pvc cassandra-data-pvc -n "$NAMESPACE" --ignore-not-found=true
            else
                log_info "Mevcut Cassandra deployment kullanılacak."
                return 0
            fi
        fi
    else
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
    fi
    
    # Cassandra YAML syntax kontrolü
    log_info "Cassandra YAML syntax kontrol ediliyor..."
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        if ! rancher kubectl apply --dry-run=client -f "$CASSANDRA_YAML" &> /dev/null; then
            log_error "Cassandra YAML dosyasında syntax hatası var."
            exit 1
        fi
    else
        if ! kubectl apply --dry-run=client -f "$CASSANDRA_YAML" &> /dev/null; then
            log_error "Cassandra YAML dosyasında syntax hatası var."
            exit 1
        fi
    fi
    
    log_success "Cassandra YAML dosyası doğrulandı."
    
    # Cassandra'yı deploy et
    log_info "Cassandra deploy ediliyor..."
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        rancher kubectl apply -f "$CASSANDRA_YAML"
    else
        kubectl apply -f "$CASSANDRA_YAML"
    fi
    
    # Cassandra'nın hazır olmasını bekle
    log_info "Cassandra'nın hazır olması bekleniyor (maksimum 10 dakika)..."
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        if rancher kubectl wait --for=condition=ready pod -l app=cassandra -n "$NAMESPACE" --timeout=600s; then
            log_success "Cassandra hazır."
        else
            log_error "Cassandra hazır olmadı. Logları kontrol edin."
            rancher kubectl get pods -n "$NAMESPACE" -l app=cassandra
            rancher kubectl describe pods -l app=cassandra -n "$NAMESPACE"
            exit 1
        fi
    else
        if kubectl wait --for=condition=ready pod -l app=cassandra -n "$NAMESPACE" --timeout=600s; then
            log_success "Cassandra hazır."
        else
            log_error "Cassandra hazır olmadı. Logları kontrol edin."
            kubectl get pods -n "$NAMESPACE" -l app=cassandra
            kubectl describe pods -l app=cassandra -n "$NAMESPACE"
            exit 1
        fi
    fi
    
    # Cassandra'nın tamamen başlamasını bekle
    log_info "Cassandra servisinin tamamen başlaması bekleniyor..."
    sleep 30
    
    # Cassandra keyspace'ini oluştur
    log_info "Cassandra keyspace oluşturuluyor..."
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        rancher kubectl exec -n "$NAMESPACE" deployment/cassandra -- cqlsh -e "CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};" || {
            log_warning "Keyspace oluşturulamadı, Cassandra henüz tam hazır olmayabilir."
            log_info "Keyspace'i manuel olarak oluşturabilirsiniz:"
            log_info "rancher kubectl exec -n $NAMESPACE deployment/cassandra -- cqlsh -e \"CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};\""
        }
    else
        kubectl exec -n "$NAMESPACE" deployment/cassandra -- cqlsh -e "CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};" || {
            log_warning "Keyspace oluşturulamadı, Cassandra henüz tam hazır olmayabilir."
            log_info "Keyspace'i manuel olarak oluşturabilirsiniz:"
            log_info "kubectl exec -n $NAMESPACE deployment/cassandra -- cqlsh -e \"CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};\""
        }
    fi
    
    log_success "Cassandra deployment tamamlandı."
}

# Rancher'a özel YAML uygula
deploy_rancher_yaml() {
    log_info "Rancher YAML dosyası uygulanıyor..."
    
    if [[ ! -f "$YAML_FILE" ]]; then
        log_error "Glowroot YAML dosyası bulunamadı: $YAML_FILE"
        exit 1
    fi
    
    # Mevcut Glowroot deployment'ını kontrol et
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        if rancher kubectl get deployment glowroot -n "$NAMESPACE" &> /dev/null; then
            log_warning "Glowroot deployment zaten mevcut."
            read -p "Glowroot'u yeniden deploy etmek istiyor musunuz? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Mevcut Glowroot deployment siliniyor..."
                rancher kubectl delete deployment glowroot -n "$NAMESPACE" --ignore-not-found=true
                rancher kubectl delete pvc glowroot-data-pvc -n "$NAMESPACE" --ignore-not-found=true
            else
                log_info "Mevcut Glowroot deployment kullanılacak."
                return 0
            fi
        fi
    else
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
    
    # Cassandra pod'larının hazır olmasını bekle
    log_info "Cassandra pod'larının hazır olması bekleniyor..."
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        rancher kubectl wait --for=condition=ready pod -l app=cassandra -n "$NAMESPACE" --timeout=300s
    else
        kubectl wait --for=condition=ready pod -l app=cassandra -n "$NAMESPACE" --timeout=300s
    fi
    
    # Glowroot pod'larının hazır olmasını bekle
    log_info "Glowroot pod'larının hazır olması bekleniyor (maksimum 5 dakika)..."
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
    echo "URL: http://glowroot.test.local" | tee -a "$LOG_FILE"
    echo "Ingress IP: $INGRESS_IP" | tee -a "$LOG_FILE"
    echo "Namespace: $NAMESPACE" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Service Endpoints ===" | tee -a "$LOG_FILE"
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        rancher kubectl get services -n "$NAMESPACE" -o wide | tee -a "$LOG_FILE"
    else
        kubectl get services -n "$NAMESPACE" -o wide | tee -a "$LOG_FILE"
    fi
    echo | tee -a "$LOG_FILE"
    
    echo "=== Pod Durumu ===" | tee -a "$LOG_FILE"
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        rancher kubectl get pods -n "$NAMESPACE" -o wide | tee -a "$LOG_FILE"
    else
        kubectl get pods -n "$NAMESPACE" -o wide | tee -a "$LOG_FILE"
    fi
    echo | tee -a "$LOG_FILE"
    
    echo "=== Kullanışlı Komutlar ===" | tee -a "$LOG_FILE"
    echo "Glowroot logları:" | tee -a "$LOG_FILE"
    if command -v rancher &> /dev/null && [[ -n "$RANCHER_API_TOKEN" ]]; then
        echo "rancher kubectl logs -f deployment/glowroot -n $NAMESPACE" | tee -a "$LOG_FILE"
        echo "Cassandra logları:" | tee -a "$LOG_FILE"
        echo "rancher kubectl logs -f deployment/cassandra -n $NAMESPACE" | tee -a "$LOG_FILE"
        echo | tee -a "$LOG_FILE"
        echo "Glowroot pod'una bağlanma:" | tee -a "$LOG_FILE"
        echo "rancher kubectl exec -it \$(rancher kubectl get pods -n $NAMESPACE -l app=glowroot -o jsonpath='{.items[0].metadata.name}') -n $NAMESPACE -- /bin/bash" | tee -a "$LOG_FILE"
        echo "Cassandra pod'una bağlanma:" | tee -a "$LOG_FILE"
        echo "rancher kubectl exec -it \$(rancher kubectl get pods -n $NAMESPACE -l app=cassandra -o jsonpath='{.items[0].metadata.name}') -n $NAMESPACE -- cqlsh" | tee -a "$LOG_FILE"
    else
        echo "kubectl logs -f deployment/glowroot -n $NAMESPACE" | tee -a "$LOG_FILE"
        echo "Cassandra logları:" | tee -a "$LOG_FILE"
        echo "kubectl logs -f deployment/cassandra -n $NAMESPACE" | tee -a "$LOG_FILE"
        echo | tee -a "$LOG_FILE"
        echo "Glowroot pod'una bağlanma:" | tee -a "$LOG_FILE"
        echo "kubectl exec -it \$(kubectl get pods -n $NAMESPACE -l app=glowroot -o jsonpath='{.items[0].metadata.name}') -n $NAMESPACE -- /bin/bash" | tee -a "$LOG_FILE"
        echo "Cassandra pod'una bağlanma:" | tee -a "$LOG_FILE"
        echo "kubectl exec -it \$(kubectl get pods -n $NAMESPACE -l app=cassandra -o jsonpath='{.items[0].metadata.name}') -n $NAMESPACE -- cqlsh" | tee -a "$LOG_FILE"
    fi
    echo | tee -a "$LOG_FILE"
    
    echo "=== DNS Ayarları ===" | tee -a "$LOG_FILE"
    echo "glowroot.test.local adresini $INGRESS_IP IP'sine yönlendirin" | tee -a "$LOG_FILE"
    echo "Örnek: echo '$INGRESS_IP glowroot.test.local' >> /etc/hosts" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "Log dosyası: $LOG_FILE" | tee -a "$LOG_FILE"
}

# Ana fonksiyon
main() {
    log_info "=== RANCHER GLOWROOT APM DEPLOYMENT BAŞLATILIYOR (CASSANDRA DESTEKLİ) ==="
    log_info "Tarih: $(date)"
    log_info "Log dosyası: $LOG_FILE"
    echo
    
    check_rancher_config
    get_rancher_cluster_info
    setup_rancher_namespace
    setup_storage
    deploy_cassandra
    deploy_rancher_yaml
    monitor_rancher_deployment
    show_rancher_access_info
    
    log_success "=== RANCHER GLOWROOT APM BAŞARIYLA DEPLOY EDİLDİ! ==="
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