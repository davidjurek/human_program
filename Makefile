.PHONY: setup test clean

setup:
	@if ! command -v xcodegen &> /dev/null; then \
		echo "xcodegen not found, installing via Homebrew..."; \
		brew install xcodegen; \
	fi
	xcodegen generate

test:
	xcodebuild test \
		-scheme HumanProgram \
		-destination 'platform=iOS Simulator,name=iPhone 15'

clean:
	rm -rf HumanProgram.xcodeproj
