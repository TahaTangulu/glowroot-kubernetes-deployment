#!/bin/bash

# Glowroot APM Docker Deployment Script (Cassandra Destekli)
# Bu script Docker ortamında Glowroot'u çalıştırır

set -euo pipefail

# Script konfigürasyonu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="glowroot-apm"
CASSANDRA_CONTAINER="cassandra-db"
IMAGE_NAME="glowroot/glowroot-central:latest"
CASSANDRA_IMAGE="cassandra:3.11"
NETWORK_NAME="glowroot-network"
VOLUME_NAME="glowroot-data"
CASSANDRA_VOLUME="cassandra-data"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/tmp/glowroot_docker_${TIMESTAMP}.log"

# Port konfigürasyonu
WEB_PORT="4000"
COLLECTOR_PORT="8181"
CASSANDRA_PORT="9042"

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
    
    # Docker versiyonu
    if command -v docker &> /dev/null; then
        log_info "Docker: $(docker --version)"
    else
        log_error "Docker bulunamadı!"
        exit 1
    fi
    
    # Docker Compose versiyonu
    if command -v docker-compose &> /dev/null; then
        log_info "Docker Compose: $(docker-compose --version)"
    else
        log_warning "Docker Compose bulunamadı. Sadece Docker kullanılacak."
    fi
    
    # Disk alanı kontrolü
    DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    log_info "Disk alanı: ${DISK_GB}GB available"
    
    if [[ "$DISK_GB" -lt 10 ]]; then
        log_warning "Disk alanı az (${DISK_GB}GB). En az 10GB önerilir (Cassandra için)."
    fi
}

# Docker servisini kontrol et
check_docker_service() {
    log_info "Docker servisi kontrol ediliyor..."
    
    if ! docker info &> /dev/null; then
        log_error "Docker servisi çalışmıyor. Başlatılıyor..."
        
        # Docker servisini başlat
        if command -v systemctl &> /dev/null; then
            sudo systemctl start docker
            sudo systemctl enable docker
        elif command -v service &> /dev/null; then
            sudo service docker start
        else
            log_error "Docker servisini manuel olarak başlatın."
            exit 1
        fi
        
        # Servisin başlamasını bekle
        sleep 5
        
        if ! docker info &> /dev/null; then
            log_error "Docker servisi başlatılamadı."
            exit 1
        fi
    fi
    
    log_success "Docker servisi çalışıyor."
}

# Docker network oluştur
setup_docker_network() {
    log_info "Docker network kontrol ediliyor..."
    
    if ! docker network ls | grep -q "$NETWORK_NAME"; then
        log_info "Docker network oluşturuluyor: $NETWORK_NAME"
        docker network create "$NETWORK_NAME"
        log_success "Network oluşturuldu."
    else
        log_info "Network zaten mevcut: $NETWORK_NAME"
    fi
}

# Docker volume'ları oluştur
setup_docker_volumes() {
    log_info "Docker volume'ları kontrol ediliyor..."
    
    # Glowroot volume
    if ! docker volume ls | grep -q "$VOLUME_NAME"; then
        log_info "Glowroot volume oluşturuluyor: $VOLUME_NAME"
        docker volume create "$VOLUME_NAME"
        log_success "Glowroot volume oluşturuldu."
    else
        log_info "Glowroot volume zaten mevcut: $VOLUME_NAME"
    fi
    
    # Cassandra volume
    if ! docker volume ls | grep -q "$CASSANDRA_VOLUME"; then
        log_info "Cassandra volume oluşturuluyor: $CASSANDRA_VOLUME"
        docker volume create "$CASSANDRA_VOLUME"
        log_success "Cassandra volume oluşturuldu."
    else
        log_info "Cassandra volume zaten mevcut: $CASSANDRA_VOLUME"
    fi
}

# Image'ları çek
pull_images() {
    log_info "Docker image'ları kontrol ediliyor..."
    
    # Glowroot image
    if ! docker images | grep -q "glowroot/glowroot-central"; then
        log_info "Glowroot image'ı çekiliyor..."
        docker pull "$IMAGE_NAME"
        log_success "Glowroot image çekildi."
    else
        log_info "Glowroot image zaten mevcut. Güncelleme kontrol ediliyor..."
        docker pull "$IMAGE_NAME"
        log_success "Glowroot image güncel."
    fi
    
    # Cassandra image
    if ! docker images | grep -q "cassandra:3.11"; then
        log_info "Cassandra image'ı çekiliyor..."
        docker pull "$CASSANDRA_IMAGE"
        log_success "Cassandra image çekildi."
    else
        log_info "Cassandra image zaten mevcut. Güncelleme kontrol ediliyor..."
        docker pull "$CASSANDRA_IMAGE"
        log_success "Cassandra image güncel."
    fi
}

# Mevcut container'ları kontrol et ve durdur
check_existing_containers() {
    log_info "Mevcut container'lar kontrol ediliyor..."
    
    # Cassandra container kontrolü
    if docker ps -a | grep -q "$CASSANDRA_CONTAINER"; then
        log_warning "Cassandra container '$CASSANDRA_CONTAINER' zaten mevcut."
        
        if docker ps | grep -q "$CASSANDRA_CONTAINER"; then
            log_info "Cassandra container çalışıyor. Durduruluyor..."
            docker stop "$CASSANDRA_CONTAINER"
        fi
        
        read -p "Mevcut Cassandra container'ı silmek istiyor musunuz? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cassandra container siliniyor..."
            docker rm "$CASSANDRA_CONTAINER"
            log_success "Cassandra container silindi."
        else
            log_info "Mevcut Cassandra container korunuyor."
        fi
    fi
    
    # Glowroot container kontrolü
    if docker ps -a | grep -q "$CONTAINER_NAME"; then
        log_warning "Glowroot container '$CONTAINER_NAME' zaten mevcut."
        
        if docker ps | grep -q "$CONTAINER_NAME"; then
            log_info "Glowroot container çalışıyor. Durduruluyor..."
            docker stop "$CONTAINER_NAME"
        fi
        
        read -p "Mevcut Glowroot container'ı silmek istiyor musunuz? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Glowroot container siliniyor..."
            docker rm "$CONTAINER_NAME"
            log_success "Glowroot container silindi."
        else
            log_info "Mevcut Glowroot container korunuyor."
        fi
    fi
}

# Cassandra container'ını başlat
start_cassandra_container() {
    log_info "Cassandra container'ı başlatılıyor..."
    
    # Cassandra container'ını başlat
    docker run -d \
        --name "$CASSANDRA_CONTAINER" \
        --network "$NETWORK_NAME" \
        -p "$CASSANDRA_PORT:9042" \
        -v "$CASSANDRA_VOLUME:/var/lib/cassandra" \
        -e CASSANDRA_START_RPC=true \
        -e CASSANDRA_CLUSTER_NAME=GlowrootCluster \
        -e CASSANDRA_DC=datacenter1 \
        -e CASSANDRA_RACK=rack1 \
        -e CASSANDRA_ENDPOINT_SNITCH=SimpleSnitch \
        -e CASSANDRA_SEEDS=cassandra-db \
        --restart unless-stopped \
        "$CASSANDRA_IMAGE"
    
    log_success "Cassandra container başlatıldı."
    
    # Cassandra'nın hazır olmasını bekle
    log_info "Cassandra'nın hazır olması bekleniyor (maksimum 5 dakika)..."
    local timeout=300
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if docker exec "$CASSANDRA_CONTAINER" cqlsh -e "describe keyspaces" &> /dev/null; then
            log_success "Cassandra hazır."
            break
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Cassandra başlatılıyor... ($elapsed/$timeout saniye)"
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log_error "Cassandra hazır olmadı. Logları kontrol edin."
        docker logs "$CASSANDRA_CONTAINER"
        exit 1
    fi
    
    # Cassandra keyspace'ini oluştur
    log_info "Cassandra keyspace oluşturuluyor..."
    docker exec "$CASSANDRA_CONTAINER" cqlsh -e "CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};" || {
        log_warning "Keyspace oluşturulamadı, Cassandra henüz tam hazır olmayabilir."
        log_info "Keyspace'i manuel olarak oluşturabilirsiniz:"
        log_info "docker exec $CASSANDRA_CONTAINER cqlsh -e \"CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};\""
    }
    
    log_success "Cassandra deployment tamamlandı."
}

# Glowroot container'ını başlat
start_glowroot_container() {
    log_info "Glowroot container'ı başlatılıyor..."
    
    # Container'ı başlat
    docker run -d \
        --name "$CONTAINER_NAME" \
        --network "$NETWORK_NAME" \
        -p "$WEB_PORT:4000" \
        -p "$COLLECTOR_PORT:8181" \
        -v "$VOLUME_NAME:/opt/glowroot/data" \
        -e GLOWROOT_OPTS="-Xms512m -Xmx1g -XX:+UseG1GC" \
        -e JAVA_OPTS="-Djava.security.egd=file:/dev/./urandom" \
        -e CASSANDRA_CONTACT_POINTS="$CASSANDRA_CONTAINER" \
        -e CASSANDRA_PORT="9042" \
        -e CASSANDRA_KEYSPACE="glowroot" \
        --restart unless-stopped \
        "$IMAGE_NAME"
    
    log_success "Glowroot container başlatıldı."
    
    # Glowroot'un hazır olmasını bekle
    log_info "Glowroot'un hazır olması bekleniyor (maksimum 3 dakika)..."
    local timeout=180
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if curl -s "http://localhost:$WEB_PORT" &> /dev/null; then
            log_success "Glowroot hazır."
            break
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Glowroot başlatılıyor... ($elapsed/$timeout saniye)"
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log_error "Glowroot hazır olmadı. Logları kontrol edin."
        docker logs "$CONTAINER_NAME"
        exit 1
    fi
}

# Container durumunu kontrol et
check_container_status() {
    log_info "Container durumları kontrol ediliyor..."
    
    # Cassandra durumu
    if docker ps | grep -q "$CASSANDRA_CONTAINER"; then
        log_success "Cassandra container çalışıyor."
    else
        log_error "Cassandra container çalışmıyor."
        docker logs "$CASSANDRA_CONTAINER"
        exit 1
    fi
    
    # Glowroot durumu
    if docker ps | grep -q "$CONTAINER_NAME"; then
        log_success "Glowroot container çalışıyor."
    else
        log_error "Glowroot container çalışmıyor."
        docker logs "$CONTAINER_NAME"
        exit 1
    fi
    
    # Port durumları
    log_info "Port durumları kontrol ediliyor..."
    if netstat -tuln | grep -q ":$WEB_PORT "; then
        log_success "Web port ($WEB_PORT) açık."
    else
        log_warning "Web port ($WEB_PORT) açık değil."
    fi
    
    if netstat -tuln | grep -q ":$COLLECTOR_PORT "; then
        log_success "Collector port ($COLLECTOR_PORT) açık."
    else
        log_warning "Collector port ($COLLECTOR_PORT) açık değil."
    fi
    
    if netstat -tuln | grep -q ":$CASSANDRA_PORT "; then
        log_success "Cassandra port ($CASSANDRA_PORT) açık."
    else
        log_warning "Cassandra port ($CASSANDRA_PORT) açık değil."
    fi
}

# Erişim bilgilerini göster
show_access_info() {
    log_info "=== DOCKER GLOWROOT ERİŞİM BİLGİLERİ ===" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    # IP adresini al
    HOST_IP=$(hostname -I | awk '{print $1}')
    
    echo "=== Web Arayüzü ===" | tee -a "$LOG_FILE"
    echo "URL: http://$HOST_IP:$WEB_PORT" | tee -a "$LOG_FILE"
    echo "Local: http://localhost:$WEB_PORT" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Collector Endpoint ===" | tee -a "$LOG_FILE"
    echo "URL: http://$HOST_IP:$COLLECTOR_PORT" | tee -a "$LOG_FILE"
    echo "Local: http://localhost:$COLLECTOR_PORT" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Cassandra Endpoint ===" | tee -a "$LOG_FILE"
    echo "Host: $HOST_IP" | tee -a "$LOG_FILE"
    echo "Port: $CASSANDRA_PORT" | tee -a "$LOG_FILE"
    echo "Keyspace: glowroot" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Container Bilgileri ===" | tee -a "$LOG_FILE"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Kullanışlı Komutlar ===" | tee -a "$LOG_FILE"
    echo "Glowroot logları:" | tee -a "$LOG_FILE"
    echo "docker logs -f $CONTAINER_NAME" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Cassandra logları:" | tee -a "$LOG_FILE"
    echo "docker logs -f $CASSANDRA_CONTAINER" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Glowroot container'a bağlanma:" | tee -a "$LOG_FILE"
    echo "docker exec -it $CONTAINER_NAME /bin/bash" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Cassandra container'a bağlanma:" | tee -a "$LOG_FILE"
    echo "docker exec -it $CASSANDRA_CONTAINER cqlsh" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Container'ları durdurma:" | tee -a "$LOG_FILE"
    echo "docker stop $CONTAINER_NAME $CASSANDRA_CONTAINER" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Container'ları başlatma:" | tee -a "$LOG_FILE"
    echo "docker start $CASSANDRA_CONTAINER $CONTAINER_NAME" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "Log dosyası: $LOG_FILE" | tee -a "$LOG_FILE"
}

# Ana fonksiyon
main() {
    log_info "=== DOCKER GLOWROOT APM DEPLOYMENT BAŞLATILIYOR (CASSANDRA DESTEKLİ) ==="
    log_info "Tarih: $(date)"
    log_info "Log dosyası: $LOG_FILE"
    echo
    
    check_system_info
    check_docker_service
    setup_docker_network
    setup_docker_volumes
    pull_images
    check_existing_containers
    start_cassandra_container
    start_glowroot_container
    check_container_status
    show_access_info
    
    log_success "=== DOCKER GLOWROOT APM BAŞARIYLA DEPLOY EDİLDİ! ==="
    echo
    log_info "Önemli Notlar:"
    log_info "1. Cassandra ve Glowroot birlikte çalışıyor"
    log_info "2. Container'lar otomatik olarak yeniden başlatılacak"
    log_info "3. Veriler Docker volume'larında saklanıyor"
    log_info "4. Detaylı loglar: $LOG_FILE"
    log_info "5. Cassandra keyspace'i otomatik oluşturuldu"
}

# Script'i çalıştır
main "$@" 