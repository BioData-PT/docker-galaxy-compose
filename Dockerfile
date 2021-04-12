# Copyright (c) 2021 Leiden University Medical Center
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Galaxy image inspired by galaxy/galaxy-k8s

# Build in stages
# Stage 1, create a galaxy root dir with all necessary dependencies, including
# a conda environment.
# Stage 2 copy the root dir into a new image.


ARG GALAXY_ROOT=/galaxy
ARG GALAXY_SERVER=/galaxy/server
ARG GALAXY_VENV=/galaxy/venv
ARG GALAXY_USER=galaxy
ARG PIP_EXTRA_ARGS="--no-cache-dir --compile"
ARG GALAXY_BRANCH=release_21.01
ARG BASE=debian:buster-slim
ARG DEBIAN_FRONTEND=noninteractive

###############################################################################
# Stage 1
###############################################################################

FROM $BASE as stage1

ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8

RUN apt-get update
RUN apt-get install -y --no-install-recommends \
    locales locales-all \
    python3-pip
RUN pip install ansible~=2.9

WORKDIR /tmp/ansible
ADD ./playbook.yml .
ADD ./requirements.yml .
RUN ansible-galaxy install -r requirements.yml -p roles --force-with-deps

RUN ansible-playbook -i localhost playbook.yml -v -e galaxy_root=$GALAXY_ROOT \
    -e galaxy_server_dir=$GALAXY_SERVER -e galaxy_venv_dir=$GALAXY_VENV \
    -e pip_extra_args=$PIP_EXTRA_ARGS

# Install conditional requirements:
# psycopg2 -> for postgres databases
# watchdog -> essential for some features that prevent having to restart galaxy all the time
# python-ldap -> For connection to ldap services. Very useful in company settings.
RUN cat $GALAXY_SERVER/lib/galaxy/dependencies/conditional-requirements.txt | \
    grep -E '(psycopg2|watchdog|python-ldap)'| xargs \
    $GALAXY_VENV/bin/pip install \
    --index-url https://wheels.galaxyproject.org/simple/ \
    --extra-index-url https://pypi.python.org/simple \
    $PIP_EXTRA_ARGS

WORKDIR $GALAXY_SERVER
RUN git rev-parse HEAD > GITREVISION
RUN rm -rf \
        .ci \
        .git \
        .venv/include/node \
        .venv/src/node* \
        doc \
        test \
        test-data

# Clean up *all* node_modules, including plugins.  Everything is already built+staged.
RUN find . -name "node_modules" -type d -prune -exec rm -rf '{}' +

###############################################################################
# Stage 2
###############################################################################

FROM $BASE as stage2

ARG ROOT_DIR
ARG SERVER_DIR
ARG GALAXY_USER
ARG GALAXY_VENV

# Init Env
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8

# Install python-virtualenv
RUN set -xe; \
    && echo "Acquire::http {No-Cache=True;};" > /etc/apt/apt.conf.d/no-cache \
    && apt-get -qq update && apt-get install -y --no-install-recommends \
        locales \
        vim-tiny \
        nano \
        curl \
    && locale-gen $LANG && update-locale LANG=$LANG \
    && apt-get autoremove -y && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/*

RUN set -xe; \
      adduser --system --group $GALAXY_USER \
      && mkdir -p $SERVER_DIR \
      && chown $GALAXY_USER:$GALAXY_USER $ROOT_DIR -R

WORKDIR $ROOT_DIR
# Copy galaxy files to final image
# The chown value MUST be hardcoded (see #35018 at github.com/moby/moby)
COPY --chown=galaxy:galaxy --from=server_build $ROOT_DIR .

# Expose http and uwsgi socket
EXPOSE 8080
EXPOSE 3031
USER $GALAXY_USER

ENV PATH="$GALAXY_VENV/bin:${PATH}"

# [optional] to run:
CMD uwsgi --yaml config/galaxy.yml
