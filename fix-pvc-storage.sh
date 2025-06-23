#!/bin/bash

# PVC Storage Sorunu Çözüm Scripti
# Bu script PVC storage boyutu sorununu çözer

set -e

echo "🔧 PVC Storage Sorunu Çözülüyor..."

# Mevcut PVC'leri sil
echo "🗑️ Mevcut PVC'ler siliniyor..."
kubectl delete pvc cassandra-data-pvc -n glowroot-apm --ignore-not-found=true
kubectl delete pvc glowroot-data-pvc -n glowroot-apm --ignore-not-found=true

# Deployment'ları da sil
echo "🗑️ Deployment'lar siliniyor..."
kubectl delete deployment cassandra -n glowroot-apm --ignore-not-found=true
kubectl delete deployment glowroot -n glowroot-apm --ignore-not-found=true

# Pod'ların silinmesini bekle
echo "⏳ Pod'ların silinmesi bekleniyor..."
kubectl wait --for=delete pod -l app=cassandra -n glowroot-apm --timeout=60s || true
kubectl wait --for=delete pod -l app=glowroot -n glowroot-apm --timeout=60s || true

# PV'leri de sil (eğer varsa)
echo "🗑️ PV'ler siliniyor..."
kubectl delete pv --field-selector=spec.claimRef.namespace=glowroot-apm --ignore-not-found=true

# Biraz bekle
echo "⏳ Temizlik için bekleniyor..."
sleep 10

echo "✅ Temizlik tamamlandı!"
echo ""
echo "Şimdi seçenekleriniz:"
echo "1. Minimal Cassandra (512MB memory)"
echo "2. H2 Database (Cassandra olmadan)"
echo ""

read -p "Hangi seçeneği tercih ediyorsunuz? (1/2): " choice

case $choice in
    1)
        echo "🚀 Minimal Cassandra ile devam ediliyor..."
        kubectl apply -f cassandra-deployment-minimal.yaml
        kubectl apply -f glowroot-kubernetes-deployment-fixed.yaml
        ;;
    2)
        echo "🚀 H2 Database ile devam ediliyor..."
        kubectl apply -f glowroot-h2-deployment.yaml
        ;;
    *)
        echo "❌ Geçersiz seçenek."
        exit 1
        ;;
esac

echo "✅ Deployment tamamlandı!"
echo "📋 Durum kontrolü:"
kubectl get pods -n glowroot-apm
kubectl get pvc -n glowroot-apm 