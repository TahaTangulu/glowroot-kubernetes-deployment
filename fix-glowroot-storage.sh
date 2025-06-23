#!/bin/bash

# K3s Storage Sorunu Çözüm Scripti
# Bu script K3s'de Glowroot PVC sorununu çözer

set -e

echo "🔧 K3s Storage Sorunu Çözülüyor..."

# Mevcut PVC'yi sil
echo "📦 Mevcut PVC siliniyor..."
kubectl delete pvc glowroot-data-pvc -n glowroot-apm --ignore-not-found=true

# Mevcut deployment'ı sil
echo "🚀 Mevcut deployment siliniyor..."
kubectl delete deployment glowroot -n glowroot-apm --ignore-not-found=true

# Storage class oluştur
echo "💾 Storage class oluşturuluyor..."
kubectl apply -f k3s-storage-class.yaml

# PVC'nin hazır olmasını bekle
echo "⏳ PVC hazırlanıyor..."
kubectl wait --for=condition=Bound pvc/glowroot-data-pvc -n glowroot-apm --timeout=60s

# Deployment'ı yeniden oluştur
echo "🔄 Deployment yeniden oluşturuluyor..."
kubectl apply -f glowroot-kubernetes-deployment.yaml

# Pod'un hazır olmasını bekle
echo "⏳ Pod başlatılıyor..."
kubectl wait --for=condition=Ready pod -l app=glowroot -n glowroot-apm --timeout=300s

echo "✅ Glowroot başarıyla başlatıldı!"
echo "🌐 Web UI: http://glowroot.test.local"
echo "📊 Collector: http://glowroot.test.local:8181"

# Durumu kontrol et
echo "📋 Durum kontrolü:"
kubectl get pods -n glowroot-apm
kubectl get pvc -n glowroot-apm
kubectl get services -n glowroot-apm 