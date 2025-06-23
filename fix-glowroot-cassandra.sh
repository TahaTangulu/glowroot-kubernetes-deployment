#!/bin/bash

# Glowroot + Cassandra Sorun Çözüm Scripti
# Bu script Cassandra ve Glowroot'u doğru şekilde deploy eder

set -e

echo "🔧 Glowroot + Cassandra Sorunu Çözülüyor..."

# Mevcut deployment'ları temizle
echo "🧹 Mevcut deployment'lar temizleniyor..."
kubectl delete deployment glowroot -n glowroot-apm --ignore-not-found=true
kubectl delete deployment cassandra -n glowroot-apm --ignore-not-found=true
kubectl delete pvc glowroot-data-pvc -n glowroot-apm --ignore-not-found=true
kubectl delete pvc cassandra-data-pvc -n glowroot-apm --ignore-not-found=true

# Storage class'ı uygula
echo "💾 Storage class uygulanıyor..."
kubectl apply -f k3s-storage-class.yaml

# Cassandra'yı deploy et
echo "🗄️ Cassandra deploy ediliyor..."
kubectl apply -f cassandra-deployment.yaml

# Cassandra'nın hazır olmasını bekle
echo "⏳ Cassandra başlatılıyor (bu biraz zaman alabilir)..."
kubectl wait --for=condition=Ready pod -l app=cassandra -n glowroot-apm --timeout=600s

echo "✅ Cassandra hazır!"

# Cassandra'nın tamamen başlamasını bekle
echo "⏳ Cassandra servisinin tamamen başlaması bekleniyor..."
sleep 30

# Cassandra keyspace'ini oluştur
echo "🗃️ Cassandra keyspace oluşturuluyor..."
kubectl exec -n glowroot-apm deployment/cassandra -- cqlsh -e "CREATE KEYSPACE IF NOT EXISTS glowroot WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"

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
echo "💡 Eğer glowroot.test.local erişilemiyorsa, hosts dosyasına ekle:"
echo "   echo '127.0.0.1 glowroot.test.local' | sudo tee -a /etc/hosts" 