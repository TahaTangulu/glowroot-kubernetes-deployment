#!/bin/bash

# Ultra Minimal Cassandra Deployment Script
# Bu script çok düşük memory ile Cassandra'yı deploy eder

set -e

echo "🚀 Ultra Minimal Cassandra Deployment Başlatılıyor..."

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

# PV'leri de sil
echo "🗑️ PV'ler siliniyor..."
kubectl delete pv --field-selector=spec.claimRef.namespace=glowroot-apm --ignore-not-found=true

# Biraz bekle
echo "⏳ Temizlik için bekleniyor..."
sleep 15

# Storage class'ı uygula
echo "💾 Storage class uygulanıyor..."
kubectl apply -f k3s-storage-class.yaml

# Ultra minimal Cassandra'yı deploy et
echo "🚀 Ultra minimal Cassandra deploy ediliyor..."
kubectl apply -f cassandra-ultra-minimal.yaml

# Cassandra'nın hazır olmasını bekle
echo "⏳ Cassandra başlatılıyor (ultra minimal memory ile)..."
echo "💡 Bu işlem 10-15 dakika sürebilir..."
kubectl wait --for=condition=Ready pod -l app=cassandra -n glowroot-apm --timeout=900s

echo "✅ Cassandra başarıyla başlatıldı!"

# Cassandra'nın tamamen başlamasını bekle
echo "⏳ Cassandra servisinin tamamen başlaması bekleniyor..."
sleep 90

# Cassandra keyspace'ini oluştur
echo "🗃️ Cassandra keyspace oluşturuluyor..."
for i in {1..5}; do
    echo "Deneme $i/5..."
    if kubectl exec -n glowroot-apm deployment/cassandra -- cqlsh -e "CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};" 2>/dev/null; then
        echo "✅ Keyspace başarıyla oluşturuldu!"
        break
    else
        echo "⚠️ Deneme $i başarısız, 30 saniye bekleniyor..."
        sleep 30
    fi
done

# Glowroot'u deploy et
echo "🚀 Glowroot deploy ediliyor..."
kubectl apply -f glowroot-kubernetes-deployment-fixed.yaml

# Glowroot'un hazır olmasını bekle
echo "⏳ Glowroot başlatılıyor..."
kubectl wait --for=condition=Ready pod -l app=glowroot -n glowroot-apm --timeout=300s

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
echo ""
echo "💡 Ultra Minimal Cassandra kullanılıyor:"
echo "   - Memory Limit: 256MB"
echo "   - Heap Size: 64M-128M"
echo "   - Storage: 1GB"
echo "   - Cache sizes minimized"
echo "   - Concurrent operations: 1"
echo ""
echo "💡 Eğer glowroot.test.local erişilemiyorsa, hosts dosyasına ekle:"
echo "   echo '127.0.0.1 glowroot.test.local' | sudo tee -a /etc/hosts" 