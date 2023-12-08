FROM ubuntu:22.04
RUN \
  apt-get update && \
  apt-get install -y bash ca-certificates gnupg make curl vim sudo jq && \
  curl -sL https://deb.nodesource.com/setup_18.x -o nodesource_setup.sh && \
  mkdir -p /etc/apt/keyrings && \
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && \
  apt-get install -y nodejs && \
  apt-get clean && \
  curl -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v4.35.2/yq_linux_amd64 && \
  chmod +x /usr/local/bin/yq
RUN \
  curl -q -l -o /tmp/go.tgz "https://dl.google.com/go/go1.21.4.linux-amd64.tar.gz" && \
  cd /usr/local && \
  tar -xvf /tmp/go.tgz && \
  rm -f /tmp/go.tgz && \
  cd /
RUN \
  curl -L -o /usr/local/bin/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && \
  chmod +x /usr/local/bin/minikube && \
  curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
  chmod +x /usr/local/bin/kubectl

RUN \
  curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
  chmod +x /tmp/get_helm.sh && \
  /tmp/get_helm.sh && \
  rm /tmp/get_helm.sh

RUN \
  groupadd -g 10001 dev && \
  useradd --uid 10001 -g 10001 -m dev && \
  echo 'dev ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/dev && \
  chmod 400 /etc/sudoers.d/dev

ENV PATH /usr/local/go/bin:$PATH

RUN \
  npm install -g "@bitnami/readme-generator-for-helm@2.6.0"

RUN \
  go install github.com/onsi/ginkgo/v2/ginkgo@latest

RUN \
  apt-get install -y git zsh strace lsof graphviz && \
  mv /root/go/bin/ginkgo /usr/local/bin

RUN \
  curl -L -o /tmp/ct.tar.gz https://github.com/helm/chart-testing/releases/download/v3.8.0/chart-testing_3.8.0_linux_amd64.tar.gz && \
  cd /usr/local/bin && \
  tar -xvf /tmp/ct.tar.gz ct && \
  cd / && \
  tar -xvf /tmp/ct.tar.gz etc && \
  mkdir /etc/ct && \
  mv /etc/chart_schema.yaml /etc/ct/ && \
  mv /etc/lintconf.yaml /etc/ct/ && \
  curl -o /tmp/gh.tar.gz https://github.com/cli/cli/releases/download/v2.40.0/gh_2.40.0_linux_amd64.tar.gz -L && \
  tar -zxvf gh.tar.gz && \
  mv gh_*_linux_amd64/bin/* /usr/local/bin && \
  mv gh_*_linux_amd64/share/man/man1/* /usr/local/share/main/man1/ && \
  cd

RUN \
  cd /tmp && \
  git clone https://github.com/devcontainers/features && \
  cd features/src/docker-in-docker && \
  export MOBY=true && \
  export INSTALLDOCKERBUILDX=false && \
  ./install.sh && \
  cd ../../../ && \
  rm -rf features

RUN \
  usermod -a -G docker dev

USER dev

