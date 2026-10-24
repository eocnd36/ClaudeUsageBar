APP := dist/Claude Usage Bar.app

.PHONY: test l10n build app universal run install icon snapshot clean

test: l10n
	swift test

## 모든 언어 파일에 빠진 번역이 없는지 검사
l10n:
	python3 scripts/check-localizations.py

build:
	swift build

## 현재 Mac 아키텍처용 .app + zip
app:
	./scripts/build-app.sh

## Apple Silicon + Intel 유니버설 .app + zip
universal:
	UNIVERSAL=1 ./scripts/build-app.sh

run: app
	-pkill -x ClaudeUsageBar
	open "$(APP)"

install: app
	-pkill -x ClaudeUsageBar
	rm -rf "/Applications/Claude Usage Bar.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Claude Usage Bar.app"

icon:
	swift scripts/make-icon.swift Resources/AppIcon.icns

## README용 팝오버 스크린샷 (데모 데이터 — 내 계정 정보는 들어가지 않음)
snapshot: build
	cp -R Resources/*.lproj .build/debug/
	.build/debug/ClaudeUsageBar --render-snapshot docs --demo -AppleLanguages "(en)"

clean:
	rm -rf .build dist
