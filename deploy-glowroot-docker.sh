#!/bin/bash

# Glowroot APM Docker Deployment Script
# Bu script Docker ortamında Glowroot'u çalıştırır

set -euo pipefail

# Script konfigürasyonu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="glowroot-apm"
IMAGE_NAME="glowroot/glowroot-central:latest"
NETWORK_NAME="glowroot-network"
VOLUME_NAME="glowroot-data"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/tmp/glowroot_docker_${TIMESTAMP}.log"

# Port konfigürasyonu
WEB_PORT="4000"
COLLECTOR_PORT="8181"

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
    
    if [[ "$DISK_GB" -lt 5 ]]; then
        log_warning "Disk alanı az (${DISK_GB}GB). En az 5GB önerilir."
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

# Docker volume oluştur
setup_docker_volume() {
    log_info "Docker volume kontrol ediliyor..."
    
    if ! docker volume ls | grep -q "$VOLUME_NAME"; then
        log_info "Docker volume oluşturuluyor: $VOLUME_NAME"
        docker volume create "$VOLUME_NAME"
        log_success "Volume oluşturuldu."
    else
        log_info "Volume zaten mevcut: $VOLUME_NAME"
    fi
}

# Glowroot image'ını çek
pull_glowroot_image() {
    log_info "Glowroot image'ı kontrol ediliyor..."
    
    if ! docker images | grep -q "glowroot/glowroot-central"; then
        log_info "Glowroot image'ı çekiliyor..."
        docker pull "$IMAGE_NAME"
        log_success "Image çekildi."
    else
        log_info "Image zaten mevcut. Güncelleme kontrol ediliyor..."
        docker pull "$IMAGE_NAME"
        log_success "Image güncel."
    fi
}

# Mevcut container'ı kontrol et ve durdur
check_existing_container() {
    log_info "Mevcut container kontrol ediliyor..."
    
    if docker ps -a | grep -q "$CONTAINER_NAME"; then
        log_warning "Container '$CONTAINER_NAME' zaten mevcut."
        
        # Container çalışıyor mu kontrol et
        if docker ps | grep -q "$CONTAINER_NAME"; then
            log_info "Container çalışıyor. Durduruluyor..."
            docker stop "$CONTAINER_NAME"
        fi
        
        read -p "Mevcut container'ı silmek istiyor musunuz? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Container siliniyor..."
            docker rm "$CONTAINER_NAME"
            log_success "Container silindi."
        else
            log_info "Mevcut container korunuyor."
            return 0
        fi
    fi
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
        --restart unless-stopped \
        "$IMAGE_NAME"
    
    log_success "Container başlatıldı."
}

# Container durumunu kontrol et
check_container_status() {
    log_info "Container durumu kontrol ediliyor..."
    
    # Container'ın başlamasını bekle
    log_info "Container'ın başlaması bekleniyor (maksimum 2 dakika)..."
    
    for i in {1..24}; do
        if docker ps | grep -q "$CONTAINER_NAME"; then
            log_success "Container çalışıyor."
            break
        fi
        
        if [[ $i -eq 24 ]]; then
            log_error "Container başlatılamadı."
            docker logs "$CONTAINER_NAME"
            exit 1
        fi
        
        log_info "Bekleniyor... ($i/24)"
        sleep 5
    done
    
    # Container loglarını kontrol et
    log_info "Container logları kontrol ediliyor..."
    docker logs "$CONTAINER_NAME" | tail -20 | tee -a "$LOG_FILE"
}

# Erişim bilgilerini göster
show_access_info() {
    log_info "=== GLOWROOT DOCKER ERİŞİM BİLGİLERİ ===" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    # Container IP'sini al
    CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME")
    
    echo "=== Web Arayüzü ===" | tee -a "$LOG_FILE"
    echo "URL: http://localhost:$WEB_PORT/glowroot" | tee -a "$LOG_FILE"
    echo "Container IP: $CONTAINER_IP" | tee -a "$LOG_FILE"
    echo "Container Name: $CONTAINER_NAME" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Collector API ===" | tee -a "$LOG_FILE"
    echo "URL: http://localhost:$COLLECTOR_PORT" | tee -a "$LOG_FILE"
    echo "Container URL: http://$CONTAINER_IP:8181" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Container Durumu ===" | tee -a "$LOG_FILE"
    docker ps | grep "$CONTAINER_NAME" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Kullanışlı Komutlar ===" | tee -a "$LOG_FILE"
    echo "Container logları:" | tee -a "$LOG_FILE"
    echo "docker logs -f $CONTAINER_NAME" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Container'a bağlanma:" | tee -a "$LOG_FILE"
    echo "docker exec -it $CONTAINER_NAME /bin/bash" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Container durdurma:" | tee -a "$LOG_FILE"
    echo "docker stop $CONTAINER_NAME" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Container başlatma:" | tee -a "$LOG_FILE"
    echo "docker start $CONTAINER_NAME" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    echo "Container silme:" | tee -a "$LOG_FILE"
    echo "docker rm -f $CONTAINER_NAME" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "=== Java Uygulamasına Agent Ekleme ===" | tee -a "$LOG_FILE"
    echo "java -javaagent:/path/to/glowroot.jar \\" | tee -a "$LOG_FILE"
    echo "     -Dglowroot.collector.host=localhost \\" | tee -a "$LOG_FILE"
    echo "     -Dglowroot.collector.port=$COLLECTOR_PORT \\" | tee -a "$LOG_FILE"
    echo "     -jar your-application.jar" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    echo "Log dosyası: $LOG_FILE" | tee -a "$LOG_FILE"
}

# Health check
health_check() {
    log_info "Health check yapılıyor..."
    
    # Container'ın çalışır durumda olduğunu kontrol et
    if docker ps | grep -q "$CONTAINER_NAME"; then
        log_success "Container çalışıyor."
        
        # Web port'unu kontrol et
        if curl -s http://localhost:$WEB_PORT/glowroot &> /dev/null; then
            log_success "Web arayüzü erişilebilir."
        else
            log_warning "Web arayüzü henüz hazır değil."
        fi
        
        # Collector port'unu kontrol et
        if curl -s http://localhost:$COLLECTOR_PORT &> /dev/null; then
            log_success "Collector API erişilebilir."
        else
            log_warning "Collector API henüz hazır değil."
        fi
    else
        log_error "Container çalışmıyor."
        exit 1
    fi
}

# Docker Compose dosyası oluştur (opsiyonel)
create_docker_compose() {
    log_info "Docker Compose dosyası oluşturuluyor..."
    
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  glowroot:
    image: glowroot/glowroot-central:latest
    container_name: $CONTAINER_NAME
    ports:
      - "$WEB_PORT:4000"
      - "$COLLECTOR_PORT:8181"
    volumes:
      - $VOLUME_NAME:/opt/glowroot/data
    environment:
      - GLOWROOT_OPTS=-Xms512m -Xmx1g -XX:+UseG1GC
      - JAVA_OPTS=-Djava.security.egd=file:/dev/./urandom
    restart: unless-stopped
    networks:
      - glowroot-network

volumes:
  $VOLUME_NAME:
    external: true

networks:
  glowroot-network:
    external: true
EOF
    
    log_success "Docker Compose dosyası oluşturuldu: docker-compose.yml"
    log_info "Kullanım: docker-compose up -d"
}

# Ana fonksiyon
main() {
    log_info "=== GLOWROOT APM DOCKER DEPLOYMENT BAŞLATILIYOR ==="
    log_info "Tarih: $(date)"
    log_info "Log dosyası: $LOG_FILE"
    echo
    
    check_system_info
    check_docker_service
    setup_docker_network
    setup_docker_volume
    pull_glowroot_image
    check_existing_container
    start_glowroot_container
    check_container_status
    health_check
    show_access_info
    create_docker_compose
    
    log_success "=== GLOWROOT APM DOCKER BAŞARIYLA DEPLOY EDİLDİ! ==="
    echo
    log_info "Önemli Notlar:"
    log_info "1. Web arayüzü: http://localhost:$WEB_PORT/glowroot"
    log_info "2. Collector API: http://localhost:$COLLECTOR_PORT"
    log_info "3. Veriler $VOLUME_NAME volume'unda saklanıyor"
    log_info "4. Detaylı loglar: $LOG_FILE"
    log_info "5. Docker Compose dosyası oluşturuldu"
}

# Script'i çalıştır
main "$@" 