#!/bin/bash

# Cassandra OOM Sorunu Çözüm Scripti
# Bu script Cassandra'nın memory sorununu çözer

set -e

echo "🔧 Cassandra OOM Sorunu Çözülüyor..."

# Mevcut Cassandra deployment'ını sil
echo "🗑️ Mevcut Cassandra deployment siliniyor..."
kubectl delete deployment cassandra -n glowroot-apm --ignore-not-found=true
kubectl delete pvc cassandra-data-pvc -n glowroot-apm --ignore-not-found=true

# Pod'ların silinmesini bekle
echo "⏳ Pod'ların silinmesi bekleniyor..."
kubectl wait --for=delete pod -l app=cassandra -n glowroot-apm --timeout=60s || true

# Güncellenmiş Cassandra deployment'ını uygula
echo "🚀 Güncellenmiş Cassandra deployment uygulanıyor..."
kubectl apply -f cassandra-deployment.yaml

# Cassandra'nın hazır olmasını bekle
echo "⏳ Cassandra başlatılıyor (düşük memory ile)..."
kubectl wait --for=condition=Ready pod -l app=cassandra -n glowroot-apm --timeout=600s

echo "✅ Cassandra başarıyla başlatıldı!"

# Cassandra'nın tamamen başlamasını bekle
echo "⏳ Cassandra servisinin tamamen başlaması bekleniyor..."
sleep 45

# Cassandra keyspace'ini oluştur
echo "🗃️ Cassandra keyspace oluşturuluyor..."
kubectl exec -n glowroot-apm deployment/cassandra -- cqlsh -e "CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};" || {
    echo "⚠️ Keyspace oluşturulamadı, Cassandra henüz tam hazır olmayabilir."
    echo "💡 Manuel olarak oluşturabilirsiniz:"
    echo "kubectl exec -n glowroot-apm deployment/cassandra -- cqlsh -e \"CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};\""
}

# Durumu kontrol et
echo "📋 Durum kontrolü:"
kubectl get pods -n glowroot-apm
kubectl get pvc -n glowroot-apm

echo "✅ Cassandra OOM sorunu çözüldü!"
echo "💡 Memory ayarları:"
echo "   - Heap Size: 256M"
echo "   - Max Heap: 512M"
echo "   - Container Limit: 1Gi" 