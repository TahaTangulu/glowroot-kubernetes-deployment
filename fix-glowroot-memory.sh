#!/bin/bash

# Glowroot Memory Sorunu Çözüm Scripti
# Bu script Cassandra OOM sorununu çözer

set -e

echo "🔧 Glowroot Memory Sorunu Çözülüyor..."
echo ""

echo "Seçenekler:"
echo "1. Minimal Cassandra (512MB memory limit)"
echo "2. H2 Database (Cassandra olmadan)"
echo ""

read -p "Hangi seçeneği tercih ediyorsunuz? (1/2): " choice

case $choice in
    1)
        echo "🚀 Minimal Cassandra ile devam ediliyor..."
        
        # Mevcut deployment'ları temizle
        echo "🧹 Mevcut deployment'lar temizleniyor..."
        kubectl delete deployment cassandra -n glowroot-apm --ignore-not-found=true
        kubectl delete deployment glowroot -n glowroot-apm --ignore-not-found=true
        kubectl delete pvc cassandra-data-pvc -n glowroot-apm --ignore-not-found=true
        kubectl delete pvc glowroot-data-pvc -n glowroot-apm --ignore-not-found=true
        
        # Pod'ların silinmesini bekle
        echo "⏳ Pod'ların silinmesi bekleniyor..."
        kubectl wait --for=delete pod -l app=cassandra -n glowroot-apm --timeout=60s || true
        kubectl wait --for=delete pod -l app=glowroot -n glowroot-apm --timeout=60s || true
        
        # Minimal Cassandra deployment'ını uygula
        echo "🚀 Minimal Cassandra deployment uygulanıyor..."
        kubectl apply -f cassandra-deployment-minimal.yaml
        
        # Cassandra'nın hazır olmasını bekle
        echo "⏳ Cassandra başlatılıyor (minimal memory ile)..."
        kubectl wait --for=condition=Ready pod -l app=cassandra -n glowroot-apm --timeout=600s
        
        echo "✅ Cassandra başarıyla başlatıldı!"
        
        # Cassandra'nın tamamen başlamasını bekle
        echo "⏳ Cassandra servisinin tamamen başlaması bekleniyor..."
        sleep 60
        
        # Cassandra keyspace'ini oluştur
        echo "🗃️ Cassandra keyspace oluşturuluyor..."
        kubectl exec -n glowroot-apm deployment/cassandra -- cqlsh -e "CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};" || {
            echo "⚠️ Keyspace oluşturulamadı, Cassandra henüz tam hazır olmayabilir."
            echo "💡 Manuel olarak oluşturabilirsiniz:"
            echo "kubectl exec -n glowroot-apm deployment/cassandra -- cqlsh -e \"CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};\""
        }
        
        # Glowroot'u deploy et
        echo "🚀 Glowroot deploy ediliyor..."
        kubectl apply -f glowroot-kubernetes-deployment-fixed.yaml
        
        # Glowroot'un hazır olmasını bekle
        echo "⏳ Glowroot başlatılıyor..."
        kubectl wait --for=condition=Ready pod -l app=glowroot -n glowroot-apm --timeout=300s
        
        ;;
        
    2)
        echo "🚀 H2 Database ile devam ediliyor..."
        
        # Mevcut deployment'ları temizle
        echo "🧹 Mevcut deployment'lar temizleniyor..."
        kubectl delete deployment cassandra -n glowroot-apm --ignore-not-found=true
        kubectl delete deployment glowroot -n glowroot-apm --ignore-not-found=true
        kubectl delete pvc cassandra-data-pvc -n glowroot-apm --ignore-not-found=true
        kubectl delete pvc glowroot-data-pvc -n glowroot-apm --ignore-not-found=true
        
        # Pod'ların silinmesini bekle
        echo "⏳ Pod'ların silinmesi bekleniyor..."
        kubectl wait --for=delete pod -l app=cassandra -n glowroot-apm --timeout=60s || true
        kubectl wait --for=delete pod -l app=glowroot -n glowroot-apm --timeout=60s || true
        
        # H2 Database ile Glowroot'u deploy et
        echo "🚀 H2 Database ile Glowroot deploy ediliyor..."
        kubectl apply -f glowroot-h2-deployment.yaml
        
        # Glowroot'un hazır olmasını bekle
        echo "⏳ Glowroot başlatılıyor..."
        kubectl wait --for=condition=Ready pod -l app=glowroot -n glowroot-apm --timeout=300s
        
        ;;
        
    *)
        echo "❌ Geçersiz seçenek. Script sonlandırılıyor."
        exit 1
        ;;
esac

echo "✅ Glowroot başarıyla başlatıldı!"

# Durumu kontrol et
echo "📋 Final durum kontrolü:"
echo "--- Pods ---"
kubectl get pods -n glowroot-apm
echo ""
echo "--- Services ---"
kubectl get services -n glowroot-apm
echo ""
echo "--- PVCs ---"
kubectl get pvc -n glowroot-apm
echo ""
echo "--- Ingress ---"
kubectl get ingress -n glowroot-apm

echo ""
echo "🎉 Kurulum tamamlandı!"
echo "🌐 Web UI: http://glowroot.test.local"
echo "📊 Collector: http://glowroot.test.local:8181"

if [[ $choice -eq 1 ]]; then
    echo "💡 Minimal Cassandra kullanılıyor:"
    echo "   - Memory Limit: 512MB"
    echo "   - Heap Size: 128M-256M"
    echo "   - Storage: 2GB"
elif [[ $choice -eq 2 ]]; then
    echo "💡 H2 Database kullanılıyor:"
    echo "   - Memory Limit: 512MB"
    echo "   - No external database required"
    echo "   - Storage: 5GB"
fi

echo ""
echo "💡 Eğer glowroot.test.local erişilemiyorsa, hosts dosyasına ekle:"
echo "   echo '127.0.0.1 glowroot.test.local' | sudo tee -a /etc/hosts" 