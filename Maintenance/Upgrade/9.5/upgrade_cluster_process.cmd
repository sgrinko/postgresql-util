@echo off
chcp 65001
set PGCLIENTENCODING=UTF8
REM текущий путь запуска cmd файла
SET PATH_CURRENT=%~dp0
CD "%PATH_CURRENT%"
REM Запоминаем время старта обновления (для статистики)
SET UPGSTART=%TIME%
REM Пути к БД и бинарникам
SET PGDATA_OLD=D:\PostgresData_9.4
SET PGDATA_NEW=D:\PostgresData_9.5
SET PGBIN_OLD=C:\Program Files\PostgreSQL\9.4\bin
SET PGBIN_NEW=C:\Program Files\PostgresPro\9.5\bin
REM параметры для инициализации кластера БД
SET PGLOCALE=English, United States
SET PGENCODING=UTF8
REM сколько процов использовать для обновления
SET PGCORE=8
REM сколько процов использовать для сбора статистики
SET PGCOREV=4
D:
SET PATH=%PATH%;%PGBIN_NEW%;

REM останавливаем 9.5
net stop postgresql-x64-9.5
if %ERRORLEVEL% == 0 goto initdb
if %ERRORLEVEL% == 2 goto initdb
echo ===========================================
echo Service "postgresql-x64-9.5" failed to stop
echo ===========================================
goto endscript

:initdb
REM создаем кластер заново с нужными нам настройками
REM Подготавливаем папку для восстановления архива. Удаляем всё
copy /Y "%PGDATA_NEW%\postgresql.conf" "%PATH_CURRENT%\postgresql.conf"
rd /S /Q "%PGDATA_NEW%\base"
rd /S /Q "%PGDATA_NEW%\global"
rd /S /Q "%PGDATA_NEW%\pg_clog"
rd /S /Q "%PGDATA_NEW%\pg_dynshmem"
rd /S /Q "%PGDATA_NEW%\pg_log"
rd /S /Q "%PGDATA_NEW%\pg_logical"
rd /S /Q "%PGDATA_NEW%\pg_multixact"
rd /S /Q "%PGDATA_NEW%\pg_notify"
rd /S /Q "%PGDATA_NEW%\pg_replslot"
rd /S /Q "%PGDATA_NEW%\pg_serial"
rd /S /Q "%PGDATA_NEW%\pg_snapshots"
rd /S /Q "%PGDATA_NEW%\pg_stat"
rd /S /Q "%PGDATA_NEW%\pg_stat_tmp"
rd /S /Q "%PGDATA_NEW%\pg_subtrans"
rd /S /Q "%PGDATA_NEW%\pg_tblspc"
rd /S /Q "%PGDATA_NEW%\pg_twophase"
rd /S /Q "%PGDATA_NEW%\pg_xlog"
rd /S /Q "%PGDATA_NEW%\pg_commit_ts"
del /Q "%PGDATA_NEW%\*.*"
REM устанавливаем с нужной локалью
"%PGBIN_NEW%\initdb.exe" -U postgres -D %PGDATA_NEW% -E %PGENCODING% --locale="%PGLOCALE%"
if %ERRORLEVEL% == 0 goto prepare1
echo ===========================================
echo Init cluster postgresql 9.5 failed
echo ===========================================
goto endscript


:prepare1
REM восстанавливаем исходный файл настроек с нужным портом
copy /Y "%PATH_CURRENT%\postgresql.conf" "%PGDATA_NEW%\postgresql.conf" 
if %ERRORLEVEL% == 0 goto prepare2
echo ===========================================
echo copy postgresql.conf failed
echo ===========================================
goto endscript

:prepare2
REM копируем туда pg_hba.conf
copy /Y %PGDATA_OLD%\pg_hba.conf %PGDATA_NEW%\pg_hba.conf
if %ERRORLEVEL% == 0 goto prepare3
echo ===========================================
echo copy pg_hba.conf failed
echo ===========================================
goto endscript

:prepare3
REM копируем туда pg_ident.conf
copy /Y %PGDATA_OLD%\pg_ident.conf %PGDATA_NEW%\pg_ident.conf
if %ERRORLEVEL% == 0 goto prepare4
echo ===========================================
echo copy pg_ident.conf failed
echo ===========================================
goto endscript

:prepare4
REM создаём файл чтения статистики по всем БД
"%PGBIN_OLD%\psql.exe" -h localhost -U "postgres" -t -A -o upgrade_dump_stat_old.sql -c "select '\c ' || datname || E'\nCREATE EXTENSION IF NOT EXISTS dump_stat;\n\\o dump_stat_' || datname || E'.sql\n' || E'select dump_statistic();\n' from pg_database where datistemplate = false and datname <> 'postgres';"
REM создаём файл вливания статистики на новый сервер...
"%PGBIN_OLD%\psql.exe" -h localhost -U "postgres" -t -A -o upgrade_dump_stat_new.sql -c "select '\c ' || datname || E'\nCREATE EXTENSION IF NOT EXISTS dump_stat;\n\\i dump_stat_' || datname || E'.sql\n' from pg_database where datistemplate = false and datname <> 'postgres';"
REM выполняем сформированный файл - upgrade_dump_stat_old.sql
"%PGBIN_OLD%\psql.exe" -h localhost -U "postgres" -t -A -f "upgrade_dump_stat_old.sql"

REM копируем туда новую версию postgresql.conf
copy /Y %PGDATA_OLD%\postgresql_new.conf %PGDATA_NEW%\postgresql.conf
if %ERRORLEVEL% == 0 goto stop_9_4
echo ===========================================
echo copy postgresql.conf failed
echo ===========================================
goto endscript

:stop_9_4
net stop postgresql-x64-9.4
if %ERRORLEVEL% == 0 goto check
if %ERRORLEVEL% == 2 goto check
echo ===========================================
echo Service "postgresql-x64-9.4" failed to stop
echo ===========================================
goto endscript

:check
REM проверка перед обновлением...
echo ==========================================================================================
echo =========                                                                   ==============
echo =========                                                                   ==============
echo =========                         UPGRADE CHECK                             ==============
echo =========                                                                   ==============
echo =========                                                                   ==============
echo ==========================================================================================
"%PGBIN_NEW%\pg_upgrade.exe" --old-datadir "%PGDATA_OLD%" --new-datadir "%PGDATA_NEW%" --old-bindir "%PGBIN_OLD%" --new-bindir "%PGBIN_NEW%" --old-port 5432 --new-port 5433 --verbose --username postgres --check
if %ERRORLEVEL% == 0 goto upgrade_cluster
echo ===========================================
echo pg_upgrade check failed
echo ===========================================
goto endscript

:upgrade_cluster
REM сам процесс... ( --jobs 8 -> запуск на 8 ядрах)
echo ==========================================================================================
echo =========                                                                   ==============
echo =========                                                                   ==============
echo =========                        UPGRADE START!!!                           ==============
echo =========                                                                   ==============
echo =========                                                                   ==============
echo ==========================================================================================
"%PGBIN_NEW%\pg_upgrade.exe" --old-datadir "%PGDATA_OLD%" --new-datadir "%PGDATA_NEW%" --old-bindir "%PGBIN_OLD%" --new-bindir "%PGBIN_NEW%" --old-port 5432 --new-port 5433 --verbose --username postgres --link --retain --jobs %PGCORE%
if %ERRORLEVEL% == 0 goto start_9_5
echo ===========================================
echo pg_upgrade cluster failed
echo ===========================================
goto endscript

:start_9_5
REM запускаем сервис
net start postgresql-x64-9.5
if %ERRORLEVEL% == 0 goto endprocess
echo ===========================================
echo Service "postgresql-x64-9.5" failed to start
echo ===========================================
goto endscript

:endprocess
echo ==========================================================================================
echo =========                                                                   ==============
echo =========                         UPGRADE END                               ==============
echo =========                                                                   ==============
echo ==========================================================================================
REM заносим статистику на новый сервер - upgrade_dump_stat_new.sql
"%PGBIN_NEW%\psql.exe" -h localhost -U "postgres" -t -A -f "upgrade_dump_stat_new.sql"
echo ==========================================================================================
echo =========                                                                   ==============
echo Start process at %UPGSTART%
echo End process at %TIME%
echo =========                                                                   ==============
echo ==========================================================================================
echo ==========================================================================================
echo =========                      job_prewarm                                  ==============
REM заполняем кэш данных нужными объектами
"%PGBIN_NEW%\psql.exe" -h localhost -U "postgres" -d sparkmes -c "select public.job_prewarm();"
echo =========                                                                   ==============
echo ==========================================================================================
REM запускаем обновление статистики
"%PGBIN_NEW%\vacuumdb.exe" -U postgres -p 5432 -j %PGCOREV% --all --analyze-in-stages
:endscript
pause
