```bash
$ timedatectl
               Local time: Mon 2025-09-15 03:08:31 UTC
           Universal time: Mon 2025-09-15 03:08:31 UTC
                 RTC time: Mon 2025-09-15 03:08:31
                Time zone: Etc/UTC (UTC, +0000)
System clock synchronized: yes
              NTP service: active
          RTC in local TZ: no


$ timedatectl list-timezones | grep Europe
Europe/Sofia
Europe/Stockholm
Europe/Tallinn
Europe/Tirane
Europe/Tiraspol
Europe/Ulyanovsk
Europe/Uzhgorod
Europe/Vaduz
Europe/Vatican
Europe/Vienna
Europe/Vilnius
Europe/Volgograd
Europe/Warsaw
Europe/Zagreb
Europe/Zaporozhye
Europe/Zurich


$ sudo timedatectl set-timezone Europe/Zurich

$ timedatectl
               Local time: Mon 2025-09-15 05:09:23 CEST
           Universal time: Mon 2025-09-15 03:09:23 UTC
                 RTC time: Mon 2025-09-15 03:09:23
                Time zone: Europe/Zurich (CEST, +0200)
System clock synchronized: yes
              NTP service: active
          RTC in local TZ: no
```