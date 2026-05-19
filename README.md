# Langfuse sur Kubernetes

Installation / upgrade rapide de Langfuse sur Kubernetes avec :

- Helm
- TLS via cert-manager
- IngressClass `public`
- PostgreSQL embarqué
- Redis/Valkey embarqué
- ClickHouse embarqué
- S3/MinIO embarqué
- workers scalables pour les évaluations RAG

URL cible :

```txt
https://langfuse.example.com
````

---

## 1. Prérequis

```bash
kubectl get nodes
helm version
kubectl get clusterissuer
kubectl get ingressclass
```

Attendu :

```txt
ClusterIssuer: letsencrypt-prod
IngressClass: public
```

Vérifier :

```bash
kubectl get clusterissuer letsencrypt-prod
kubectl get ingressclass public
```

---

## 2. Installation / upgrade

Créer le namespace :

```bash
kubectl create namespace langfuse --dry-run=client -o yaml | kubectl apply -f -
```

Ajouter le repo Helm :

```bash
helm repo add langfuse https://langfuse.github.io/langfuse-k8s
helm repo update
```

Générer les secrets et le fichier de valeurs :

```bash
./generate.sh
```

Cela crée `.env` (ignoré par git, permissions 600) avec les secrets aléatoires, puis `values-langfuse.yaml`.

Pour régénérer de nouveaux secrets :

```bash
./generate.sh
```

Installer ou upgrader :

```bash
helm upgrade --install langfuse langfuse/langfuse \
  -n langfuse \
  -f values-langfuse.yaml \
  --wait \
  --timeout 15m
```

---

## 3. Vérification

```bash
kubectl get pods -n langfuse -o wide
kubectl get ingress -n langfuse
kubectl get certificate -n langfuse
```

Attendu :

```txt
langfuse-tls   True
```

Tester l’URL :

```bash
curl -Ik https://langfuse.example.com
```

---

## 4. Vérifier Redis

Tester Redis depuis Kubernetes :

```bash
REDIS_PASSWORD="$(grep '^REDIS_PASSWORD=' .env | cut -d'"' -f2)"

kubectl run redis-test -n langfuse --rm -i --restart=Never \
  --image=redis:7-alpine -- \
  redis-cli -h langfuse-redis-primary -p 6379 \
  -a "${REDIS_PASSWORD}" ping
```

Attendu :

```txt
PONG
```

---

## 5. Redémarrage propre après installation

Après le premier boot, redémarrer web + workers pour éviter les faux positifs Redis au démarrage :

```bash
kubectl rollout restart deploy/langfuse-web deploy/langfuse-worker -n langfuse

kubectl rollout status deploy/langfuse-web -n langfuse
kubectl rollout status deploy/langfuse-worker -n langfuse
```

Vérifier les erreurs Redis récentes :

```bash
kubectl logs -n langfuse deploy/langfuse-worker --since=3m \
  | grep -Ei "redis error|ECONNREFUSED|ETIMEDOUT|Connection to redis lost" \
  || echo "OK: pas d'erreur Redis récente"
```

---

## 6. Utilisation rapide

Ouvrir :

```txt
https://langfuse.example.com
```

Créer le premier compte admin via l’interface web.

Ensuite créer un projet, puis générer :

* Public Key
* Secret Key

---

## 7. Test SDK Python

Installer le SDK :

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install langfuse
```

Créer `test-langfuse.py` :

```python
from langfuse import Langfuse

langfuse = Langfuse(
    public_key="pk-lf-REPLACE_ME",
    secret_key="sk-lf-REPLACE_ME",
    host="https://langfuse.example.com",
)

trace = langfuse.trace(
    name="test-rag",
    user_id="test-user",
    metadata={"env": "k8s"},
)

generation = trace.generation(
    name="llm-response",
    model="test-model",
    input="Bonjour, résume ce document.",
    output="Résumé court du document.",
)

generation.end()

trace.score(
    name="quality",
    value=0.95,
    comment="Test score depuis SDK Python",
)

langfuse.flush()
print("OK")
```

Exécuter :

```bash
python test-langfuse.py
```

---

## 8. Scaling des workers pour évaluations RAG

Voir la charge :

```bash
kubectl top pods -n langfuse
```

Scaler temporairement les workers :

```bash
kubectl scale deploy/langfuse-worker -n langfuse --replicas=8
```

Vérifier :

```bash
kubectl get pods -n langfuse | grep worker
```

Si c’est mieux, modifier durablement `values-langfuse.yaml` :

```yaml
langfuse:
  worker:
    replicas: 8
    hpa:
      enabled: true
      minReplicas: 8
      maxReplicas: 16
```

Puis appliquer :

```bash
helm upgrade --install langfuse langfuse/langfuse \
  -n langfuse \
  -f values-langfuse.yaml \
  --wait \
  --timeout 15m
```

---

## 9. Logs utiles

Web :

```bash
kubectl logs -n langfuse deploy/langfuse-web --tail=100 -f
```

Workers :

```bash
kubectl logs -n langfuse deploy/langfuse-worker --tail=100 -f
```

Redis :

```bash
kubectl logs -n langfuse statefulset/langfuse-redis-primary --tail=100
```

PostgreSQL :

```bash
kubectl logs -n langfuse statefulset/langfuse-postgresql --tail=100
```

ClickHouse :

```bash
kubectl logs -n langfuse statefulset/langfuse-clickhouse-shard0 --tail=100
```

---

## 10. Diagnostic rapide

Pods :

```bash
kubectl get pods -n langfuse -o wide
```

Services :

```bash
kubectl get svc -n langfuse
```

Ingress :

```bash
kubectl describe ingress -n langfuse langfuse
```

Certificat :

```bash
kubectl describe certificate -n langfuse langfuse-tls
```

Events :

```bash
kubectl get events -n langfuse --sort-by=.lastTimestamp | tail -50
```

Redis endpoint :

```bash
kubectl get svc -n langfuse langfuse-redis-primary -o wide
kubectl get endpoints -n langfuse langfuse-redis-primary -o wide
```

---

## 11. Upgrade Langfuse

Mettre à jour le repo :

```bash
helm repo update
```

Voir la version actuelle :

```bash
helm list -n langfuse
```

Upgrade :

```bash
helm upgrade --install langfuse langfuse/langfuse \
  -n langfuse \
  -f values-langfuse.yaml \
  --wait \
  --timeout 15m
```

---

## 12. Désinstallation

Attention : peut supprimer les workloads. Les volumes persistants peuvent rester selon la StorageClass.

```bash
helm uninstall langfuse -n langfuse
```

Supprimer le namespace :

```bash
kubectl delete namespace langfuse
```

Lister les PVC restants :

```bash
kubectl get pvc -A | grep langfuse
```

---

## Notes tuning RAG / évaluations

Pour des évaluations RAG lentes :

1. augmenter `langfuse.worker.replicas`
2. surveiller CPU/RAM des workers
3. vérifier Redis
4. vérifier ClickHouse
5. éviter d’évaluer toutes les traces en live
6. préférer batch scoring sur échantillon
7. pousser les scores ensuite dans Langfuse

Exemple :

```bash
kubectl scale deploy/langfuse-worker -n langfuse --replicas=8
kubectl top pods -n langfuse
```
