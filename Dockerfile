FROM osrf/ros:humble-desktop

ARG USER_UID=1000
ARG USER_GID=1000
ARG USERNAME=dev

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-humble-rmw-zenoh-cpp \
        python3-colcon-common-extensions \
        python3-rosdep \
        python3-pip \
        ros-dev-tools \
        git \
        vim \
        nano \
        tmux \
        less \
        iputils-ping \
        net-tools \
        iproute2 \
        sudo \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

USER ${USERNAME}
WORKDIR /home/${USERNAME}/ros2_ws

RUN mkdir -p /home/${USERNAME}/ros2_ws/src \
    && echo "source /opt/ros/humble/setup.bash" >> /home/${USERNAME}/.bashrc \
    && echo "[ -f /home/${USERNAME}/ros2_ws/install/setup.bash ] && source /home/${USERNAME}/ros2_ws/install/setup.bash" >> /home/${USERNAME}/.bashrc \
    && echo "export RMW_IMPLEMENTATION=rmw_zenoh_cpp" >> /home/${USERNAME}/.bashrc \
    && echo "export ZENOH_SESSION_CONFIG_URI=/home/${USERNAME}/zenoh_config/session.json5" >> /home/${USERNAME}/.bashrc

CMD ["bash"]
