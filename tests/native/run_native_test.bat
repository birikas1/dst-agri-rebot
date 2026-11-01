@echo off
chcp 65001 >nul
rem One-click native smoke test: isolated copy of DST under tests\native, never your saves/mods.
cd /d "%~dp0\..\.."
where py >nul 2>nul && (set PY=py -3) || (set PY=python)
echo [1/4] Lua regression suites
%PY% tests\run_tests.py
echo [2/4] Staging isolated DST runtime (first run copies the game, may take minutes)
%PY% tests\native\stage.py || goto :fail
echo [3/4] Native run 1: world, prefabs, real actions, primary transfer, save
%PY% tests\native\run.py
echo [4/4] Native run 2: reload the saved world and verify restored state
%PY% tests\native\run.py
echo.
echo Done. Logs are in tests\native\logs. Look for COMPLETE / FAIL lines above.
pause
exit /b 0
:fail
echo Staging failed.
pause
exit /b 1
