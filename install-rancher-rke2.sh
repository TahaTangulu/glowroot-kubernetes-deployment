#!/bin/bash

# RKE2 + Rancher Kurulum Script'i
# Bu script RKE2 üzerine Rancher'ı kurar

set -euo pipefail

# Renk kodları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log fonksiyonları
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1"
}

# RKE2 kubeconfig'ini ayarla
setup_kubeconfig() {
    log_info "RKE2 kubeconfig ayarlanıyor..."
    
    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
    
    # kubectl'in çalıştığını doğrula
    if kubectl get nodes &> /dev/null; then
        log_success "kubectl çalışıyor"
        kubectl get nodes
    else
        log_error "kubectl çalışmıyor. RKE2 kurulumunu kontrol edin."
        exit 1
    fi
}

# Helm kurulumu
install_helm() {
    log_info "Helm kuruluyor..."
    
    if ! command -v helm &> /dev/null; then
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        log_success "Helm kuruldu"
    else
        log_info "Helm zaten kurulu: $(helm version --short)"
    fi
}

# Cert-manager kurulumu
install_cert_manager() {
    log_info "Cert-manager kuruluyor..."
    
    # Eski cert-manager kurulumunu temizle
    log_info "Eski cert-manager kurulumu kontrol ediliyor..."
    if helm list -n cert-manager | grep -q cert-manager; then
        log_warning "Eski cert-manager kurulumu bulundu. Siliniyor..."
        helm uninstall cert-manager -n cert-manager --ignore-not-found=true
        kubectl delete namespace cert-manager --ignore-not-found=true
        sleep 10
    fi
    
    # Mevcut cert-manager CRD'lerini temizle (eğer varsa)
    log_info "Mevcut cert-manager CRD'leri temizleniyor..."
    kubectl delete crd certificaterequests.cert-manager.io --ignore-not-found=true
    kubectl delete crd certificates.cert-manager.io --ignore-not-found=true
    kubectl delete crd challenges.acme.cert-manager.io --ignore-not-found=true
    kubectl delete crd clusterissuers.cert-manager.io --ignore-not-found=true
    kubectl delete crd issuers.cert-manager.io --ignore-not-found=true
    kubectl delete crd orders.acme.cert-manager.io --ignore-not-found=true
    
    # Biraz bekle
    sleep 5
    
    # Jetstack repo ekle
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    
    # Cert-manager'i kur
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.15.4 \
        --set installCRDs=true \
        --wait --timeout=10m
    
    # Cert-manager'in hazır olmasını bekle
    log_info "Cert-manager'in hazır olması bekleniyor..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
    
    log_success "Cert-manager kuruldu"
}

# Rancher kurulumu
install_rancher() {
    log_info "Rancher kuruluyor..."
    
    # Eski Rancher kurulumunu temizle
    log_info "Eski Rancher kurulumu kontrol ediliyor..."
    if helm list -n cattle-system | grep -q rancher; then
        log_warning "Eski Rancher kurulumu bulundu. Siliniyor..."
        helm uninstall rancher -n cattle-system --ignore-not-found=true
        kubectl delete namespace cattle-system --ignore-not-found=true
        sleep 10
    fi
    
    # Namespace oluştur
    kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Helm repo ekle
    helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
    helm repo update
    
    # Sunucu IP'sini al ve hosts dosyasına ekle
    SERVER_IP=$(hostname -I | awk '{print $1}')
    HOSTNAME="rancher.local"
    
    log_info "Sunucu IP: $SERVER_IP"
    log_info "Hostname: $HOSTNAME"
    
    # Hosts dosyasına ekle
    if ! grep -q "$HOSTNAME" /etc/hosts; then
        echo "$SERVER_IP $HOSTNAME" >> /etc/hosts
        log_info "Hosts dosyasına $HOSTNAME eklendi"
    fi
    
    # Rancher'ı kur
    helm install rancher rancher-latest/rancher \
        --namespace cattle-system \
        --set hostname="$HOSTNAME" \
        --set bootstrapPassword=admin123 \
        --wait --timeout=10m
    
    log_success "Rancher kuruldu"
}

# Rancher durumunu kontrol et
check_rancher_status() {
    log_info "Rancher durumu kontrol ediliyor..."
    
    # Pod'ların hazır olmasını bekle
    kubectl wait --for=condition=ready pod -l app=rancher -n cattle-system --timeout=300s
    
    # Pod'ları listele
    kubectl get pods -n cattle-system
    
    # Service'leri listele
    kubectl get services -n cattle-system
}

# Erişim bilgilerini göster
show_access_info() {
    log_info "=== RANCHER ERİŞİM BİLGİLERİ ==="
    
    SERVER_IP=$(hostname -I | awk '{print $1}')
    HOSTNAME="rancher.local"
    
    echo
    echo "=== Web Arayüzü ==="
    echo "URL: https://$HOSTNAME"
    echo "IP: $SERVER_IP"
    echo "Kullanıcı: admin"
    echo "Şifre: admin123"
    echo
    echo "=== Hosts Dosyası ==="
    echo "Eğer erişim sorunu yaşarsanız:"
    echo "echo '$SERVER_IP $HOSTNAME' >> /etc/hosts"
    echo
    echo "=== kubectl Komutları ==="
    echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
    echo "kubectl get pods -n cattle-system"
    echo "kubectl logs -f deployment/rancher -n cattle-system"
    echo
    echo "=== Rancher CLI Kurulumu ==="
    echo "curl -Lo rancher https://github.com/rancher/cli/releases/latest/download/rancher-linux-amd64"
    echo "chmod +x rancher"
    echo "sudo mv rancher /usr/local/bin/"
    echo
    echo "=== Glowroot Kurulumu ==="
    echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
    echo "./deploy-glowroot-server.sh"
}

# Ana fonksiyon
main() {
    log_info "=== RKE2 + RANCHER KURULUMU BAŞLATILIYOR ==="
    echo
    
    setup_kubeconfig
    install_helm
    install_cert_manager
    install_rancher
    check_rancher_status
    show_access_info
    
    log_success "=== RANCHER BAŞARIYLA KURULDU! ==="
    echo
    log_info "Tarayıcıdan https://rancher.local adresine gidin"
    log_info "Kullanıcı: admin, Şifre: admin123"
    log_info "Eğer erişim sorunu yaşarsanız: echo '$(hostname -I | awk '{print $1}') rancher.local' >> /etc/hosts"
}

# Script'i çalıştır
main "$@" 