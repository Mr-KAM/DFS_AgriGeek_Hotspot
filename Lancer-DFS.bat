@echo off
title DFS - AgriGeek Hotspot
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Configurer-DFS.ps1" %*
