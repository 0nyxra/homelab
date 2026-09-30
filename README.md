# 🌸 homelab

![Page d'accueil de mon lab](docs/homepage.png)

Mon lab perso sur un **Raspberry Pi 5** : DNS, VPN, reverse proxy avec HTTPS, supervision et une page d'accueil rose (évidemment).
Le but : apprendre en construisant quelque chose d'utile, en documentant chaque problème rencontré et comment je l'ai réglé.

## Services

| | Service | À quoi ça sert |
|---|---|---|
| 🕳️ | **Pi-hole** | DNS local + blocage des pubs sur tout le réseau |
| 🔐 | **WireGuard** (wg-easy) | VPN pour accéder au lab de n'importe où |
| 🦆 | **DuckDNS** | Nom de domaine qui suit mon IP publique si elle change |
| 🔀 | **Nginx Proxy Manager** | Reverse proxy + certificats HTTPS (Let's Encrypt) |
| 📊 | **Uptime Kuma** | Surveille tous les services et m'alerte par courriel |
| 🏠 | **Homepage** | Page d'accueil du lab, avec l'état de chaque service |
| 🖥️ | **Portainer** | Gestion des conteneurs Docker |

## Architecture

```
  📱 Téléphone (dehors)
        │  tunnel WireGuard (UDP 51820)
        ▼
     Internet
        │
  [ Routeur ] ── seul port ouvert : UDP 51820 ──┐
        │                                       │
  ┌─────┴────────────────────────────────────┐  │
  │  Raspberry Pi 5 (192.168.40.46)          │◄─┘
  │  UFW + Fail2ban                          │
  │                                          │
  │  Ports publiés : 53 · 80 · 443 · 51820   │
  │                                          │
  │  wg-easy ............ VPN                │
  │  Pi-hole ............ DNS (:53)          │
  │  Nginx Proxy Manager  HTTPS (:443)       │
  │     │  réseau Docker « proxy »           │
  │     ├─ home.*      → homepage:3000       │
  │     ├─ pihole.*    → pihole:80           │
  │     ├─ kuma.*      → uptime-kuma:3001    │
  │     ├─ portainer.* → portainer:9000      │
  │     └─ vpn.*       → wg-easy:51821       │
  │        (réseau « wireguard_wg »)         │
  │  DuckDNS ............ met à jour l'IP    │
  └──────────────────────────────────────────┘
        │
  Mes appareils à la maison
```

Chaque service a son nom en HTTPS (`https://pihole.MONDOMAINE.duckdns.org`). Pi-hole répond l'IP **locale** du Pi pour ces noms, donc le trafic reste à la maison. NPM joint chaque service par son **nom de conteneur** : aucune interface web n'a de port publié.

## Structure du dépôt

```
homelab/
├── docker-compose.yml        # Pi-hole + Portainer
├── .env.example              # modèle pour les mots de passe
├── wireguard/                # wg-easy (+ correctif nftables)
├── duckdns/                  # mise à jour du DNS dynamique
├── proxy/                    # Nginx Proxy Manager
├── uptime-kuma/              # supervision
├── homepage/                 # page d'accueil + config (thème rose 🌸)
├── configs/systeme/          # SSH, UFW, Fail2ban, rkhunter
├── docs/
│   ├── durcissement.md       # durcissement complet du Pi, pas à pas
│   └── homepage.png
└── images/                   # captures avant / après du durcissement
```

## Installation

```bash
git clone https://github.com/Chahdmk/homelab.git
cd homelab
cp .env.example .env          # mettre ses propres mots de passe
docker volume create portainer_data
docker network create proxy   # réseau partagé entre NPM et les services
docker compose up -d          # Pi-hole + Portainer
```

Les autres services se déploient comme **stacks dans Portainer**, à partir du `docker-compose.yml` de chaque dossier (déployer wg-easy **avant** NPM et Uptime Kuma, qui rejoignent son réseau `wireguard_wg`). Les secrets (token DuckDNS, clé API Pi-hole, mot de passe de base de données) se définissent dans les **variables d'environnement de la stack** : ils ne sont jamais écrits dans les fichiers.

Remplacer `MONDOMAINE` par son sous-domaine DuckDNS, `192.168.40.46` par l'IP de son Pi, et `MAVILLE` / les coordonnées dans `homepage/config/widgets.yaml`.

## 🔒 Sécurité

- **Un seul port ouvert sur Internet : UDP 51820** (WireGuard). Tout le reste n'est accessible qu'à la maison ou via le VPN.
- **Aucun secret dans le dépôt** : `.env` est dans le `.gitignore`, et les stacks utilisent des variables `${...}`.
- **Vrais certificats HTTPS** sans ouvrir les ports 80/443 : défi DNS Let's Encrypt via DuckDNS.
- **SSH par clé seulement**, root interdit.
- **Pare-feu UFW** (refus par défaut, SSH limité au LAN et au VPN) + **Fail2ban** sur SSH.
- **Mises à jour de sécurité automatiques** (unattended-upgrades).
- **Seulement 4 ports publiés sur le Pi** (53, 80, 443, 51820) au lieu de 12 : les services passent par le réseau Docker `proxy`.
- **Admin Portainer et NPM** liées à `127.0.0.1`, accessibles seulement par tunnel SSH.
- **rkhunter** : 0 rootkit. **Lynis : hardening index 67.**
- Mots de passe d'application (Gmail, Pi-hole) au lieu des vrais mots de passe, tous rangés dans un gestionnaire.

➡️ Tout le détail, avec les commandes et les captures avant / après : **[docs/durcissement.md](docs/durcissement.md)**

![Ports fermés : avant / après](images/09-test-ports-avant-apres.png)

## 📓 Journal de bord

Les vrais problèmes rencontrés, et comment je les ai réglés.

<details>
<summary><b>Pi-hole ignorait les requêtes du réseau</b></summary>

Depuis le Pi, tout marchait (`nslookup google.com 127.0.0.1`). Mais dès que Pi-hole devenait le DNS du réseau, mes appareils n'avaient plus Internet. La réponse était dans les logs :
```
dnsmasq: ignoring query from non-local network 192.168.40.81
```
Pi-hole tourne dans le réseau interne de Docker, alors les requêtes de mon PC arrivaient d'un réseau qu'il ne considérait pas comme « local ».

✅ `FTLCONF_dns_listeningMode: 'ALL'`, à condition de ne **jamais** ouvrir le port 53 sur le routeur.
Bonus : `WEBPASSWORD` ne fonctionne plus depuis Pi-hole v6. Remplacé par `FTLCONF_webserver_api_password`, avec le mot de passe dans le `.env`.
</details>

<details>
<summary><b>Portainer : intégration au compose et mot de passe oublié</b></summary>

Portainer tournait à part. Je l'ai intégré au docker-compose en le branchant sur son volume existant (`external: true`), pour garder mon compte.

Mot de passe oublié ? Il existe un outil officiel :
```bash
docker compose stop portainer
docker run --rm -v portainer_data:/data portainer/helper-reset-password
docker compose start portainer
```
</details>

<details>
<summary><b>Coupure de courant : diagnostic réseau</b></summary>

Plus d'Internet après une panne. Diagnostic couche par couche : `ping` vers la passerelle (OK), puis `ping 8.8.8.8` (échec). Le problème était donc la ligne du fournisseur, pas le Pi. Ensuite, pertes de paquets intermittentes : deux `ping -t` en parallèle (passerelle et Internet) pour savoir si ça venait du Wi-Fi ou de la ligne.

Leçon : un Pi en Wi-Fi qui sert de DNS rend tout le réseau dépendant du Wi-Fi. Ethernet est dans la liste.
</details>

<details>
<summary><b>WireGuard : wg0 ne démarrait pas (noyau 6.18 sans iptables legacy)</b></summary>

L'assistant de wg-easy restait bloqué, et les logs affichaient `wg show wg0 dump : No such device`. En remontant plus haut dans les logs :
```
modprobe: FATAL: Module ip_tables not found in directory /lib/modules/6.18.39+rpt-rpi-2712
iptables v1.8.13 (legacy): can't initialize iptables table `nat': Table does not exist
```
- Le module WireGuard était bien chargé (`lsmod | grep wireguard`).
- La vraie cause : wg-easy utilise **iptables legacy**, mais le noyau 6.18 de Raspberry Pi OS n'a plus que **nftables**. C'est un bug connu (issues #2627 et #2645 de wg-easy).
- 1er essai : modifier les hooks dans l'interface, mais l'enregistrement échouait.

✅ Le conteneur contient déjà `iptables-nft`. Je fais pointer `/etc/alternatives/iptables*` vers les versions `-nft` dans le `command` de la stack, donc c'est refait à chaque démarrage (voir `wireguard/docker-compose.yml`). Vérifié avec `iptables --version`, qui affiche `(nf_tables)`, et avec `wg show`.

Leçon : le premier message d'erreur n'est pas toujours la cause. Il faut remonter jusqu'à la première commande qui échoue.
</details>

<details>
<summary><b>DuckDNS : ne plus dépendre de mon IP publique</b></summary>

Mon IP publique peut changer (après une panne, par exemple), et le VPN ne marcherait plus. Un conteneur DuckDNS met mon domaine à jour toutes les 5 minutes, et wg-easy utilise le domaine au lieu de l'IP. Le token DuckDNS reste dans les variables de la stack Portainer.
</details>

<details>
<summary><b>Uptime Kuma : supervision et alertes</b></summary>

- Sondes HTTP pour les interfaces web, et une sonde **DNS** qui interroge vraiment Pi-hole : une page web qui s'affiche ne veut pas dire que le DNS répond.
- Alertes par courriel via le SMTP de Gmail, avec un **mot de passe d'application**.
- Mot de passe Kuma perdu (je l'avais écrasé avec le mot de passe d'application Gmail dans mon gestionnaire) : `docker exec -it uptime-kuma npm run reset-password`.

Leçons : une entrée par secret dans le gestionnaire, avec une note qui dit à quoi elle sert. Et si Internet tombe à la maison, aucune alerte ne peut partir.
</details>

<details>
<summary><b>Homepage : widgets, bug de voyant et thème rose 🌸</b></summary>

- Config en YAML sur le Pi, montée dans le conteneur (*bind mount*). Je modifie le fichier, et la page se met à jour.
- Widget Pi-hole avec une clé API passée par `{{HOMEPAGE_VAR_PIHOLE_KEY}}`, jamais écrite dans le fichier.
- Le voyant de Pi-hole affichait `HPE_CLOSED_CONNECTION: Data after Connection: close`. Pi-hole répondait bien `200 OK`, mais son serveur web envoie des données après avoir annoncé la fermeture de la connexion, ce que Node.js refuse. ✅ `ping` au lieu de `siteMonitor` pour Pi-hole.
- Thème : `custom.css` avec un dégradé pastel, la police Quicksand et des titres en cursive. Premier essai raté : Homepage peint son fond sur `#page_wrapper` / `#inner_wrapper` par-dessus `body`, et le thème sombre restait mémorisé dans le navigateur.
</details>

<details>
<summary><b>Reverse proxy, domaine local et HTTPS 🔒</b></summary>

1. **Premier essai avec `.lab`** : une seule ligne dans Pi-hole répond l'IP du Pi pour tous les noms en `.lab` (`address=/lab/192.168.40.46`), et Nginx Proxy Manager redirige chaque nom vers le bon service.
2. **Passage à un vrai domaine** : `.lab` n'est pas une vraie extension, donc pas de certificat HTTPS possible et certains outils (navigateurs, gestionnaires de mots de passe) le traitent mal. Maintenant : `*.MONDOMAINE.duckdns.org`, avec Pi-hole qui répond l'IP **locale** pour ce domaine.
3. **Certificat joker Let's Encrypt** obtenu par un **défi DNS** DuckDNS : aucun port à ouvrir. Clé ECDSA, renouvellement automatique.

Pièges rencontrés :
- `did not find expected key` : une erreur d'indentation YAML. `docker compose config` valide le fichier avant de lancer quoi que ce soit.
- DuckDNS ne peut poser qu'un seul enregistrement TXT à la fois : il faut demander **seulement** le joker.
- « Publicly Accessible » dans NPM veut seulement dire « sans liste d'accès ». Ce qui expose vraiment un service, c'est le routeur.
- Homepage refuse les noms inconnus : il faut les ajouter à `HOMEPAGE_ALLOWED_HOSTS`.
- Edge ouvrait les noms locaux dans mon profil du cégep (commutation automatique de profil). ✅ Une exception « Don't switch » dans `edge://settings/profiles`.
</details>

<details>
<summary><b>Durcissement SSH : ma config était ignorée</b></summary>

Après avoir mis `PasswordAuthentication no` dans `/etc/ssh/sshd_config.d/99-hardening.conf`, je pouvais **encore** me connecter par mot de passe.

- Dans OpenSSH, **la première valeur lue l'emporte**, et les fichiers de `sshd_config.d/` sont lus par ordre alphabétique.
- `50-cloud-init.conf` (créé par Raspberry Pi OS) contenait `PasswordAuthentication yes` et passait avant mon `99-`.

✅ Renommé en `01-hardening.conf`. Vérifié avec `sshd -T` (la config réellement appliquée) et un test forcé :
```
ssh -o PubkeyAuthentication=no chahd@192.168.40.46
Permission denied (publickey).
```
Leçon : vérifier ce qui est **appliqué**, pas seulement ce qui est écrit.
</details>

<details>
<summary><b>Docker passait par-dessus mon pare-feu</b></summary>

UFW activé, port 3001 non autorisé… et pourtant `Test-NetConnection 192.168.40.46 -Port 3001` répondait `True`. Docker écrit ses propres règles iptables pour les ports publiés, **avant** UFW.

✅ Un réseau Docker commun `proxy` : NPM joint chaque service par son nom (`http://uptime-kuma:3001`) et les `ports:` des interfaces web sont supprimés. Pour wg-easy, c'est NPM qui rejoint son réseau `wireguard_wg`, pour ne pas risquer de casser le NAT du VPN. Résultat : 12 ports publiés → 4.

Pièges rencontrés en chemin :
- **504 Gateway Time-out** : NPM et Kuma sur le même réseau, mais NPM pointait encore vers `192.168.40.46:3001`. La connexion repassait par le Pi et UFW la bloquait. Il faut changer la destination **tout de suite** après le réseau.
- Un `docker network connect` manuel disparaît quand le conteneur est recréé : le réseau doit être dans le compose.
- Fermer les ports a rendu Homepage et Kuma tout gris : ils surveillaient encore `IP:port`. Passés aux noms de conteneurs.
- Tous mes sites en timeout, sauf en navigation privée : cache DNS d'Edge après le redémarrage de Pi-hole (`edge://net-internals/#dns`).

Détails et captures : [docs/durcissement.md](docs/durcissement.md)
</details>

## Ce que ce projet m'a appris

**Réseau** : DNS, NAT et redirection de ports, VPN WireGuard, DNS dynamique, réseaux Docker, diagnostic couche par couche (`ping`, `nslookup`, `tracert`, `Test-NetConnection`)
**Sécurité** : surface d'attaque minimale, durcissement Linux (SSH, UFW, Fail2ban, rkhunter, Lynis), gestion des secrets, certificats TLS et défi DNS, mots de passe d'application
**Linux et Docker** : Docker Compose, volumes et *bind mounts*, variables d'environnement, lecture de logs, iptables et nftables
**Supervision** : sondes HTTP et DNS, alertes SMTP
**Méthode** : lire les logs jusqu'à la vraie cause, garder un accès de secours avant de toucher au pare-feu, tout documenter

## Prochaines étapes

- [x] Pi-hole pour tout le réseau
- [x] Portainer dans le docker-compose
- [x] WireGuard testé depuis l'extérieur
- [x] DNS dynamique (DuckDNS)
- [x] Supervision + alertes (Uptime Kuma)
- [x] Page d'accueil avec widgets (Homepage)
- [x] Reverse proxy + vrai HTTPS
- [x] Durcissement du Pi (SSH, UFW, Fail2ban, ports Docker, rkhunter, Lynis)
- [ ] iTop (billetterie / gestion de services)
- [ ] Grafana + Prometheus
- [ ] Sauvegarde automatique des configs et des volumes
- [ ] Pi en Ethernet


---
*Projet en évolution constante. Si ça casse, c'est que j'apprends.* 🔧
