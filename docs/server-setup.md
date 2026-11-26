# Конфигурация виртуальной машины devops-vm

Студент: Самарцев Р. К., группа ЭФБО-09-24.

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Средство виртуализации | WSL 2 на Windows 11; экземпляр `devops-vm-samartsev` |
| Гостевая ОС | Ubuntu 24.04.5 LTS (без графической подсистемы) |
| Имя узла | `devops-vm` (FQDN `devops-vm.devops.local`) |
| Оперативная память | до 15 ГБ (динамически, общий лимит WSL 2) |
| Процессор | 14 логических ядер (общий пул WSL 2) |
| Диск | виртуальный диск VHDX, динамически расширяемый (до 1 ТБ) |

Создание и первичная настройка:

```powershell
wsl --install -d Ubuntu-24.04 --name devops-vm-samartsev
```

В `/etc/wsl.conf`: `systemd=true`, `hostname=devops-vm`, `generateHosts=false`, `default=student`; затем `wsl --terminate devops-vm-samartsev` и повторный запуск. Установлены обновления, `openssh-server`, `ufw`.

## 2. Сетевые интерфейсы

| Интерфейс | Тип | Адрес | Назначение |
|---|---|---|---|
| `eth0` | виртуальная сеть WSL (NAT) | `172.19.233.223/20`, хост — `172.19.224.1` | выход в Интернет (аналог NAT) и доступ с хоста по адресу (аналог Host-only) |
| `lo` | обратная петля | `127.0.0.1` | локальные службы |

## 3. Правило проброса портов

| Порт хоста | Порт гостевой системы | Механизм |
|---|---|---|
| `127.0.0.1:2222` | `2222` | автоматическая переадресация localhost WSL 2 (`localhostForwarding`) |

## 4. Учётные записи

| Имя | Группы | Аутентификация |
|---|---|---|
| `student` | `student`, `sudo` | пароль; вход по SSH запрещён (`AllowUsers devops`), только консоль WSL |
| `devops` | `devops`, `sudo`, `users` | только по ключу ed25519 `~/.ssh/devops_vm` (`devops-vm-key`) |

```bash
sudo adduser devops && sudo usermod -aG sudo devops
# на хосте:
ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm
ssh-copy-id -i ~/.ssh/devops_vm.pub -p 22 devops@127.0.0.1
```

Права: `~/.ssh` — 700, `~/.ssh/authorized_keys` — 600. На хосте в `~/.ssh/config` описан узел `devops` (127.0.0.1, порт 2222, пользователь devops, ключ devops_vm, `IdentitiesOnly yes`).

## 5. Служба SSH

Основной `/etc/ssh/sshd_config` не изменялся (копия — `sshd_config.backup`). Файл `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Активация по сокету отключена: `systemctl disable --now ssh.socket`, `systemctl enable --now ssh.service`; служба слушает `0.0.0.0:2222`.

## 6. Правила межсетевого экрана

Политики: `deny (incoming)`, `allow (outgoing)`; журналирование `medium`.

| Порт | Действие | Назначение |
|---|---|---|
| 2222/tcp | LIMIT | SSH |
| 80/tcp | ALLOW | HTTP |
| 443/tcp | ALLOW | HTTPS |

Имя: в `hosts` хоста — `172.19.233.223 devops.local`; на сервере в `/etc/hosts` — `127.0.1.1 devops-vm.devops.local devops-vm`.

## 7. Снимки состояния

Снимок — экспорт экземпляра (`wsl --export`); откат — `wsl --unregister devops-vm-samartsev` и `wsl --import devops-vm-samartsev <каталог> <архив>`.

| Снимок | Момент создания | Файл |
|---|---|---|
| `01-clean-install` | 2026-11-19 23:50, после установки ОС | `C:\WSL-snapshots\samartsev\01-clean-install.tar` |
| `02-keys-configured` | 2026-11-20 00:07, после настройки ключевого входа | `C:\WSL-snapshots\samartsev\02-keys-configured.tar` |
| `03-ssh-hardened` | 2026-11-20 00:30, после усиления SSH | `C:\WSL-snapshots\samartsev\03-ssh-hardened.tar` |
| `04-nginx-https` | 2026-11-20 01:07, после настройки Nginx и HTTPS | `C:\WSL-snapshots\samartsev\04-nginx-https.tar` |
| `05-docker-compose` | 2026-11-20 01:23, после развёртывания приложения в Docker Compose | `C:\WSL-snapshots\samartsev\05-docker-compose.tar` |

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Пакет | `nginx` 1.24.0 из репозитория Ubuntu (`sudo apt install -y nginx`) |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, ссылка `/etc/nginx/sites-enabled/devops-site`; ссылка `sites-enabled/default` удалена |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, каталог `755`, файлы `644` |
| Сертификат | `/etc/ssl/certs/devops.crt`, `root:root`, `644`, срок 365 дней, SAN `DNS:devops.local` |
| Закрытый ключ | `/etc/ssl/private/devops.key`, `root:root`, `600` |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |

```bash
sudo apt update && sudo apt install -y nginx
sudo mkdir -p /var/www/devops-site && sudo chown -R devops:devops /var/www/devops-site
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Текст `/etc/nginx/sites-available/devops-site`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;
    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
    error_page 404 /404.html;
    access_log /var/log/nginx/devops-site.access.log;
    error_log  /var/log/nginx/devops-site.error.log;
}
```

Содержимое доставляется с хоста сценарием `scripts/deploy.sh` (rsync с `--delete --chmod=D755,F644`). На хосте (Git Bash) rsync 3.4.4 установлен из пакетов MSYS2 в `~/bin`; сертификат для проверки — `~/devops.crt` (`scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`).

## 9. Контейнеризация

| Параметр | Значение |
|---|---|
| Docker Engine | 29.10.0 из официального репозитория `download.docker.com` (пакеты `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`); `docker.io` не используется |
| Compose | плагин `docker compose` v5.8.0 |
| Участники группы `docker` | `devops` (имеет право sudo; группа `docker` равнозначна root) |
| DNS контейнеров | `/etc/docker/daemon.json`: `{"dns": ["1.1.1.1", "8.8.8.8"]}` (особенность стенда: резолвер WSL недоступен из сетей Docker) |
| Проект | `~/app` на сервере (доставка: `rsync -avz --delete --exclude=.env app/ devops:app/`) |
| Секреты | `~/app/.env`, владелец `devops`, права `600`; создаётся только на сервере из `.env.example` |
| Публикуемые порты | `127.0.0.1:5000` → `app:5000`; порт СУБД 5432 не публикуется |
| Тома | `app_db_data` → `/var/lib/postgresql/data` |
| Сеть | `app_backend` (bridge), имена сервисов `app`, `db` |

```bash
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops      # затем новая SSH-сессия

cd ~/app
cp .env.example .env && chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
docker compose up -d --build
```

Обратный прокси — в блоке HTTPS `/etc/nginx/sites-available/devops-site` после `error_page`:

```nginx
    location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

Снимок `05-docker-compose` — 2026-11-20 01:23, `C:\WSL-snapshots\samartsev\05-docker-compose.tar` (см. раздел 7).

## 10. Ansible

Проект: каталог `ansible/` репозитория `devops-course-2026` (ветка `feature/ansible`). Запуск — из каталога `ansible/` в домашнем каталоге WSL управляющего узла (не с `/mnt/c`), чтобы подключился `ansible.cfg`.

| Параметр | Значение |
|---|---|
| Управляющий узел | WSL `devops-control`, пользователь `samartsev`, ansible-core 2.16.3 |
| Управляемый узел | `devops-vm` (Ubuntu 24.04), адрес `172.19.233.223`, SSH-порт 22 |
| Коллекции | ansible.posix 1.6.2, community.docker 4.5.0, community.general 9.5.0 (`requirements.yml`) |
| inventory bootstrap | `inventory/bootstrap.ini` — пользователь `student`, вход по паролю (только первичный запуск) |
| inventory prod | `inventory/prod.ini` — пользователь `devops`, ключ `~/.ssh/devops_vm`, sudo без пароля |
| Образ | `ghcr.io/depcil/devops-ci-app` |
| Тег (полный SHA) | `18add44121c17458066f82167cdd4945fb72bc42` |
| Порт контейнера | `127.0.0.1:5000 → 5000/tcp`, наружу только через Nginx на 80 |
| Health endpoint | `http://127.0.0.1:5000/health` на VM, `http://172.19.233.223/health` снаружи, ответ `{"status":"ok"}` |

Роли (`site.yml`, порядок важен):

- `base` — проверка платформы, базовые пакеты (в т. ч. `python3-requests`, `python3-debian`), официальный репозиторий Docker, Docker Engine;
- `ssh` — пользователь `devops`, открытый ключ, `/etc/sudoers.d/devops` (visudo), `00-ansible-hardening.conf` (вход по паролю и root запрещены), UFW: 22 и 80, deny incoming;
- `nginx` — reverse proxy на `127.0.0.1:5000`, default site отключён, `nginx -t` перед reload;
- `app` — загрузка образа по SHA, контейнер `devops-ci-app`, ожидание health.

Команды:

```bash
cd ~/devops-course-2026/ansible
ansible-galaxy collection install -r requirements.yml
# первичный запуск (один раз, пароль student вводится интерактивно)
ansible-playbook -i inventory/bootstrap.ini site.yml --ask-pass --ask-become-pass
# повторный запуск (prod.ini по умолчанию, ожидается changed=0)
ansible-playbook site.yml
# read-only аудит
ansible-playbook verify.yml
```
