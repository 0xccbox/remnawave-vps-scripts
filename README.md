# Remnawave VPS Scripts
Понятные скрипты для подготовки VPS под Remnawave Panel, Remnawave Node и Remnawave Routing Updater.

Проект рассчитан на простых пользователей, которые хотят быстро подготовить сервер под VPN-инфраструктуру на базе Remnawave без ручной настройки Linux, Docker, firewall, BBR и системных лимитов.

## Быстрый выбор

Если вы не знаете, какой скрипт запускать, начните с этого раздела.

### У меня VPS для Remnawave Node

Remnawave Node — это сервер, который принимает VPN-трафик пользователей.

Для подготовки VPS-ноды выполните:

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/vps-vpn-prep.sh) --vpn-port 443
```

### У меня VPS с панелью Remnawave

Панель Remnawave — это главный сервер управления пользователями, подписками, конфигурациями и нодами.

Для установки Routing Updater на сервер с панелью выполните:

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/routing-updater-install.sh) --start
```

### Панель Remnawave ещё не установлена

Если панели ещё нет, но вы хотите заранее подготовить файлы Routing Updater:

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/routing-updater-install.sh) --prepare
```

После установки панели нужно будет создать API token в Remnawave и запустить скрипт повторно с параметром `--start`.

## Что такое Remnawave Panel и Remnawave Node

Обычно инфраструктура Remnawave выглядит так:

```text
Пользовательское приложение
        |
        | получает подписку/config
        v
Панель Remnawave
        |
        | управляет
        v
Remnawave Node
        |
        | пропускает VPN-трафик
        v
Интернет
```

### Панель Remnawave

Панель — это главный сервер управления.

На сервере с панелью обычно находятся:

- пользователи;
- подписки;
- API панели;
- настройки нод;
- routing/config;
- база данных;
- управление всей VPN-инфраструктурой.

### Remnawave Node

Нода — это отдельный сервер, который принимает и обрабатывает VPN-трафик пользователей.

На VPS-ноду обычно не нужно ставить Routing Updater.

## Файлы в репозитории

```text
remnawave-vps-scripts/
├── README.md
├── vps-vpn-prep.sh
└── routing-updater-install.sh
```

| Файл | Назначение |
|---|---|
| `README.md` | Инструкция и описание проекта |
| `vps-vpn-prep.sh` | Подготовка VPS под Remnawave Node |
| `routing-updater-install.sh` | Установка Remnawave Routing Updater на сервер с панелью |

## Поддерживаемые системы

Рекомендуется использовать чистую VPS на одной из систем:

- Ubuntu 22.04;
- Ubuntu 24.04;
- Debian 11;
- Debian 12.

Лучший вариант для большинства пользователей — чистая Ubuntu 24.04.

## Важное предупреждение

Скрипты изменяют настройки сервера.

Они могут:

- обновлять систему;
- устанавливать пакеты;
- устанавливать Docker;
- настраивать firewall;
- включать BBR;
- менять сетевые параметры Linux;
- увеличивать системные лимиты;
- создавать swap;
- запускать Docker-контейнеры;
- предлагать перезагрузку VPS.

Рекомендуется запускать скрипты на чистой VPS.

Если сервер уже используется для важных задач, перед запуском сделайте резервную копию или snapshot у провайдера.

## Скрипт 1: подготовка VPS под Remnawave Node

Файл:

```bash
vps-vpn-prep.sh
```

Этот скрипт подготавливает VPS для дальнейшей установки Remnawave Node.

### Что делает скрипт

Скрипт выполняет базовую подготовку сервера:

- обновляет систему;
- устанавливает полезные утилиты;
- устанавливает Docker;
- включает BBR;
- настраивает сетевые параметры Linux;
- увеличивает лимиты открытых файлов;
- настраивает firewall UFW;
- открывает SSH-порт;
- открывает порты `80` и `443`;
- может открыть дополнительные VPN-порты;
- устанавливает и настраивает fail2ban;
- ограничивает размер системных логов;
- создаёт swap на слабых VPS, если мало оперативной памяти.

### Что скрипт не делает

Этот скрипт не устанавливает саму Remnawave Node.

Он только подготавливает сервер.

После выполнения этого скрипта нужно отдельно установить Remnawave Node по инструкции вашей панели Remnawave.

### Обычный запуск

Для большинства пользователей подходит команда:

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/vps-vpn-prep.sh) --vpn-port 443
```

### Если нужен другой VPN-порт

Например, если ваша нода будет использовать порт `8443`:

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/vps-vpn-prep.sh) --vpn-port 8443
```

Можно открыть несколько портов:

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/vps-vpn-prep.sh) --vpn-port 443 --vpn-port 8443 --vpn-port 2053
```

### Если Docker не нужен

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/vps-vpn-prep.sh) --no-docker --vpn-port 443
```

### Без автоматической перезагрузки

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/vps-vpn-prep.sh) --vpn-port 443 --no-reboot
```

### С автоматической перезагрузкой

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/vps-vpn-prep.sh) --vpn-port 443 --reboot
```

### XanMod kernel

По умолчанию XanMod kernel не устанавливается.

Это сделано специально, потому что на разных VPS другое ядро может работать по-разному.

Для большинства пользователей лучше использовать стандартное ядро Ubuntu/Debian + BBR.

Если вы точно понимаете, зачем вам XanMod, можно запустить:

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/vps-vpn-prep.sh) --xanmod --vpn-port 443
```

Новичкам этот вариант не рекомендуется.

## Скрипт 2: Remnawave Routing Updater

Файл:

```bash
routing-updater-install.sh
```

Routing Updater нужен для автоматического обновления routing-данных через API панели Remnawave.

Обычно он устанавливается на тот VPS, где находится панель Remnawave.

### Где нужно устанавливать Routing Updater

Правильная схема обычно такая:

```text
VPS #1: Панель Remnawave
  - Remnawave Panel
  - API
  - база данных
  - пользователи
  - Routing Updater

VPS #2: Remnawave Node
  - принимает VPN-трафик
  - Routing Updater обычно не нужен

VPS #3: Remnawave Node
  - принимает VPN-трафик
  - Routing Updater обычно не нужен
```

Если на сервере установлена только нода, Routing Updater обычно не нужен.

### Что делает скрипт Routing Updater

Скрипт:

- создаёт рабочую папку;
- создаёт `.env`;
- создаёт `docker-compose.yml`;
- спрашивает API token от панели Remnawave;
- пытается определить Docker-сеть панели;
- может работать до установки панели;
- может работать после установки панели;
- запускает контейнер Routing Updater;
- позволяет смотреть логи;
- позволяет смотреть статус;
- позволяет перезапускать контейнер;
- позволяет останавливать контейнер;
- позволяет обновлять Docker-образ.

### Если панель Remnawave ещё не установлена

Можно заранее подготовить файлы:

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/routing-updater-install.sh) --prepare
```

В этом режиме скрипт подготовит файлы, но не будет запускать контейнер без токена.

После установки панели Remnawave нужно создать API token в панели и запустить скрипт снова.

### Если панель Remnawave уже установлена

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/routing-updater-install.sh) --start
```

Скрипт спросит API token и попробует запустить Routing Updater.

### Обычный интерактивный запуск

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/routing-updater-install.sh)
```

### Посмотреть статус Routing Updater

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/routing-updater-install.sh) --status
```

### Посмотреть логи Routing Updater

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/routing-updater-install.sh) --logs
```

### Перезапустить Routing Updater

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/routing-updater-install.sh) --restart
```

### Остановить Routing Updater

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/routing-updater-install.sh) --stop
```

### Обновить Docker-образ Routing Updater

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/routing-updater-install.sh) --pull
```

После обновления образа можно перезапустить контейнер:

```bash
bash <(curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/routing-updater-install.sh) --restart
```

## Проверка после подготовки VPS

После выполнения `vps-vpn-prep.sh` можно проверить систему.

### Проверить ядро

```bash
uname -r
```

### Проверить BBR

```bash
sysctl net.ipv4.tcp_congestion_control
```

Если BBR включён, вы увидите:

```text
net.ipv4.tcp_congestion_control = bbr
```

### Проверить Docker

```bash
docker --version
```

### Проверить firewall

```bash
ufw status
```

## Безопасный способ запуска

Если вы не хотите сразу запускать скрипт через `bash <(curl ...)`, можно сначала скачать его на сервер.

Пример для `vps-vpn-prep.sh`:

```bash
curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/vps-vpn-prep.sh -o /root/vps-vpn-prep.sh
chmod +x /root/vps-vpn-prep.sh
bash /root/vps-vpn-prep.sh --vpn-port 443
```

Так проще увидеть, что именно скачалось и что именно запускается.

## Если команда ничего не делает

Проверьте, скачивается ли скрипт:

```bash
curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/vps-vpn-prep.sh | head
```

Если видите:

```text
404: Not Found
```

значит ссылка неправильная или файл не существует.

Также можно запустить с отладкой:

```bash
curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/vps-vpn-prep.sh | bash -x
```

Или с параметрами:

```bash
curl -fLs https://raw.githubusercontent.com/0xccbox/remnawave-vps-scripts/main/vps-vpn-prep.sh | bash -x -s -- --vpn-port 443
```

## Частые вопросы

### Нужно ли ставить Routing Updater на каждую ноду?

Обычно нет.

Routing Updater обычно ставится на сервер с панелью Remnawave, потому что он работает через API панели.

### Нужно ли ставить XanMod kernel?

По умолчанию нет.

Для большинства VPS достаточно стандартного ядра Ubuntu/Debian и включённого BBR.

XanMod лучше использовать только если вы понимаете, зачем он нужен, и готовы тестировать стабильность.

### Скрипт устанавливает Remnawave Panel?

Нет.

Эти скрипты не устанавливают саму панель Remnawave.

### Скрипт устанавливает Remnawave Node?

Нет.

`vps-vpn-prep.sh` только подготавливает сервер под будущую установку ноды.

### Можно ли запускать на уже рабочем сервере?

Можно, но не рекомендуется без понимания последствий.

Лучше использовать чистую VPS.

## Рекомендованный порядок установки

### Для сервера с панелью

1. Установить чистую Ubuntu 24.04.
2. Установить Remnawave Panel.
3. Создать API token в панели.
4. Запустить `routing-updater-install.sh --start`.
5. Проверить логи Routing Updater.

### Для сервера-ноды

1. Установить чистую Ubuntu 24.04.
2. Запустить `vps-vpn-prep.sh --vpn-port 443`.
3. Перезагрузить VPS, если скрипт предложит.
4. Установить Remnawave Node по инструкции панели.
5. Проверить подключение ноды к панели.

## Автор

Scripts by `0xccbox`.

## Ответственность

Вы используете эти скрипты на свой страх и риск.

Перед запуском на важном сервере сделайте резервную копию или snapshot VPS.
