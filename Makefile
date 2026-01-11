KUBERNETES_VERSION=1.32.1

lint:
	stylua -c .

test: lint
	nvim --headless --noplugin -u tests/minimal_init.vim -c "PlenaryBustedDirectory tests  { minimal_init = './tests/minimal_init.vim' }"

prepare:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim ../plenary.nvim

	# setup stylua
	curl -L -o stylua.zip https://github.com/JohnnyMorganz/StyLua/releases/latest/download/stylua-linux-x86_64.zip
	unzip stylua.zip
	rm stylua.zip
	chmod +x stylua
	sudo mv stylua /usr/local/bin/

	# setup yaml-language-server
	npm install -g yaml-language-server

generate-kubernetes: generate_kubernetes_version generate_kubernetes_resources

generate_kubernetes_resources:
	perl resources/scripts/generate_kubernetes_resources.pl > lua/yaml-companion/builtin/kubernetes/resources.lua

generate_kubernetes_version:
	perl resources/scripts/generate_kubernetes_version.pl ${KUBERNETES_VERSION} > lua/yaml-companion/builtin/kubernetes/version.lua
