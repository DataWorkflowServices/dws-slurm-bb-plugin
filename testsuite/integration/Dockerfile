FROM rockylinux:9 AS testbase

COPY requirements.txt /requirements.txt

RUN yum update -y && \
    yum in -y \
        dnf-plugins-core \
        python3 \
        python3-pip && \
    dnf check-update && \
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo && \
    dnf install -y docker-ce-cli && \
    curl -LO https://dl.k8s.io/release/v1.25.0/bin/linux/amd64/kubectl && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    pip install -r requirements.txt

RUN mkdir /reports

FROM testbase AS test

WORKDIR /tests

CMD [ \
    "pytest", \
    "--junitxml=/reports/integration.junit.xml", \
    "--html=/reports/integration.html", \
    "--gherkin-terminal-reporter", \
    "-v", "." \
]