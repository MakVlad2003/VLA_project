ARG BASE_IMAGE=nvcr.io/nvidia/isaac-lab:2.3.2
FROM ${BASE_IMAGE}

USER root
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
COPY IsaacLab-v2.3.0.tar.gz /tmp/IsaacLab-v2.3.0.tar.gz
RUN echo 'bc989537d90452108bfc12423856cebfa98e3a494b892c4d9081a994cc3b063a  /tmp/IsaacLab-v2.3.0.tar.gz' | sha256sum -c - \
    && mkdir -p /opt/isaaclab-course \
    && tar -xzf /tmp/IsaacLab-v2.3.0.tar.gz --strip-components=1 -C /opt/isaaclab-course \
    && ln -s /isaac-sim /opt/isaaclab-course/_isaac_sim \
    && /isaac-sim/python.sh -m pip uninstall -y isaaclab_contrib \
    && /isaac-sim/python.sh -m pip install --no-deps --no-build-isolation \
        -e /opt/isaaclab-course/source/isaaclab \
        -e /opt/isaaclab-course/source/isaaclab_assets \
        -e /opt/isaaclab-course/source/isaaclab_tasks \
        -e /opt/isaaclab-course/source/isaaclab_rl \
        -e /opt/isaaclab-course/source/isaaclab_mimic \
    && /isaac-sim/python.sh -m pip install --no-cache-dir gymnasium==1.2.0 starlette==0.45.3 \
    && rm /tmp/IsaacLab-v2.3.0.tar.gz

ARG PROJECT_UID=1001
ARG PROJECT_GID=1001
RUN groupadd --gid ${PROJECT_GID} vla \
    && useradd --uid ${PROJECT_UID} --gid ${PROJECT_GID} --groups 1234 \
        --create-home --home-dir /home/vla --shell /bin/bash vla

ENV HOME=/home/vla \
    ISAACLAB_PATH=/opt/isaaclab-course \
    DOCKER_USER_HOME=/home/vla
LABEL org.opencontainers.image.title="VLA course Isaac Sim" \
    vla.course.isaac-sim="5.1.0" \
    vla.course.isaac-lab="2.3.0"
USER vla
WORKDIR /opt/isaaclab-course
ENTRYPOINT ["/isaac-sim/runheadless.sh"]
