FROM osrf/ros:humble-desktop

ARG USER_UID=1000
ARG USER_GID=1000
ARG USERNAME=dev

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3-colcon-common-extensions \
        python3-rosdep \
        python3-pip \
        ros-dev-tools \
        ros-humble-zenoh-cpp-vendor \
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
        curl \
        build-essential \
        cmake \
    && rm -rf /var/lib/apt/lists/*

# Build rmw_zenoh from source (humble branch — no apt binary exists for Humble).
# Built into /opt/rmw_zenoh so users' ros2_ws stays clean.
RUN mkdir -p /opt/rmw_zenoh/src \
    && git clone --depth 1 --branch humble https://github.com/ros2/rmw_zenoh.git /opt/rmw_zenoh/src/rmw_zenoh \
    && cd /opt/rmw_zenoh \
    && . /opt/ros/humble/setup.sh \
    && rosdep update --rosdistro=humble \
    && apt-get update \
    && rosdep install --from-paths src --ignore-src -y --rosdistro humble \
    && colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release \
    && rm -rf /var/lib/apt/lists/* /opt/rmw_zenoh/build /opt/rmw_zenoh/log

# Source the rmw_zenoh overlay in the image entrypoint so non-interactive
# shells (e.g. `docker run image ros2 ...`) also pick up librmw_zenoh_cpp.so.
RUN sed -i '/source "\/opt\/ros\/\$ROS_DISTRO\/setup.bash"/a source "/opt/rmw_zenoh/install/setup.bash" --' /ros_entrypoint.sh

RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

USER ${USERNAME}
WORKDIR /home/${USERNAME}/ros2_ws

RUN mkdir -p /home/${USERNAME}/ros2_ws/src \
    && echo "source /opt/ros/humble/setup.bash" >> /home/${USERNAME}/.bashrc \
    && echo "source /opt/rmw_zenoh/install/setup.bash" >> /home/${USERNAME}/.bashrc \
    && echo "[ -f /home/${USERNAME}/ros2_ws/install/setup.bash ] && source /home/${USERNAME}/ros2_ws/install/setup.bash" >> /home/${USERNAME}/.bashrc
# NOTE: Do not export RMW_IMPLEMENTATION / ZENOH_*_CONFIG_URI from .bashrc.
# compose.yaml is the single source of truth for these. A .bashrc export
# would silently override the per-machine session config (e.g. force
# session.json5 on a remote peer that's configured to use
# session.lan.json5) for interactive shells only — a debugging nightmare.

CMD ["bash"]
