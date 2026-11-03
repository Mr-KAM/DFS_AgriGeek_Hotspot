@echo off
title DFS - Reparation du partage Internet
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Configurer-DFS.ps1" -Repair
