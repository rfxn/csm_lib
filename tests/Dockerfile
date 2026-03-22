ARG BASE_IMAGE=csm-base-debian12
FROM ${BASE_IMAGE}

COPY files/ /opt/files/
COPY tests/ /opt/tests/

WORKDIR /opt/tests
CMD ["bats", "--formatter", "tap", "/opt/tests/"]
