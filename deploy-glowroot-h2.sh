#!/bin/bash

# Glowroot H2 Database Deployment Script
# Bu script Glowroot'u H2 Database ile deploy eder (Cassandra olmadan)

set -e

echo "🚀 Glowroot H2 Database Deployment Başlatılıyor..."

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
sleep 10

# Storage class'ı uygula
echo "💾 Storage class uygulanıyor..."
kubectl apply -f k3s-storage-class.yaml

# H2 Database ile Glowroot'u deploy et
echo "🚀 H2 Database ile Glowroot deploy ediliyor..."
kubectl apply -f glowroot-h2-deployment.yaml

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
echo "💡 H2 Database kullanılıyor:"
echo "   - Memory Limit: 512MB"
echo "   - No external database required"
echo "   - Storage: 5GB"
echo "   - No OOM issues"
echo ""
echo "💡 Eğer glowroot.test.local erişilemiyorsa, hosts dosyasına ekle:"
echo "   echo '127.0.0.1 glowroot.test.local' | sudo tee -a /etc/hosts" 