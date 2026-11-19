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
