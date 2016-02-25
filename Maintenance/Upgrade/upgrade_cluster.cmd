@echo off
REM 
REM обновление с версии 9.4 до версии 9.5 
REM устанавливаем новую версию сервера на порт 5433 и новый DATA каталог D:/PostgresData_9.5
REM эта часть вручную...
REM 
RUNAS /USER:postgres "D:\Backup\PostgreSQL\upgrade_cluster_process.cmd"



