test: $(find src -type f) $(find testsuite/unit/src -type f) Dockerfile
	docker buildx build --target test -t test .
