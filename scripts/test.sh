#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -parse-as-library -module-cache-path build/module-cache Sources/DictionaryStore.swift Sources/Composition.swift Tests/CoreTests.swift -o build/CoreTests
build/CoreTests Resources/wubi.tsv
xcrun swiftc -parse-as-library -module-cache-path build/module-cache Sources/Composition.swift Sources/InputSession.swift Tests/InputTests.swift -o build/InputTests
build/InputTests
xcrun swiftc -parse-as-library -module-cache-path build/module-cache Sources/Composition.swift Sources/InputSession.swift Sources/DictionaryStore.swift Sources/PinyinDictionary.swift Sources/InputController.swift Sources/CandidatePanel.swift Sources/ModeIndicator.swift Tests/ClientTests.swift -framework AppKit -framework InputMethodKit -o build/ClientTests
build/ClientTests
xcrun swiftc -parse-as-library -module-cache-path build/module-cache Sources/DictionaryStore.swift Sources/PinyinDictionary.swift Sources/Composition.swift Sources/InputSession.swift Tests/FeatureTests.swift -o build/FeatureTests
build/FeatureTests
xcrun swiftc -parse-as-library -module-cache-path build/module-cache Sources/DictionaryStore.swift Sources/PinyinDictionary.swift Sources/Composition.swift Sources/InputSession.swift Tests/WildcardTests.swift -o build/WildcardTests
build/WildcardTests
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" -module-cache-path build/module-cache Sources/DictionaryStore.swift Sources/Preferences.swift Sources/CandidatePanel.swift Sources/ModeIndicator.swift Tests/PreferencesSmoke.swift -framework AppKit -o build/PreferencesSmoke
build/PreferencesSmoke
xcrun clang -mmacosx-version-min=14.0 Tests/NetworkTests.c Sources/NetworkGuard.c -lsandbox -o build/NetworkTests
build/NetworkTests
