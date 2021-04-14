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
ARG GALAXY_DATA=/galaxy/data
ARG GALAXY_USER=galaxy
ARG PIP_EXTRA_ARGS="--no-cache-dir --compile"
ARG GALAXY_COMMIT_ID=release_21.01
ARG BASE=debian:buster-slim
ARG DEBIAN_FRONTEND=noninteractive

###############################################################################
# Stage 1
###############################################################################

FROM $BASE as stage1

ARG GALAXY_ROOT
ARG GALAXY_SERVER
ARG GALAXY_VENV
ARG GALAXY_DATA
ARG PIP_EXTRA_ARGS
ARG GALAXY_COMMIT_ID
ARG DEBIAN_FRONTEND=noninteractive

ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8

RUN apt-get update
# Git for cloning. Pip setuptools for ansible. Virtualenv for ansible virtualenv tasks.
# Bzip2 make for client build (tar.bz2 archives, makefile).
RUN apt-get install -y --no-install-recommends \
    locales locales-all \
    git \
    python3-pip python3-setuptools python3-virtualenv \
    bzip2 make
RUN pip3 install --upgrade setuptools pip && pip3 install 'ansible>=2.9,<2.10'

WORKDIR /tmp/ansible
ENV LC_ALL en_US.UTF-8
ADD ./playbook.yml .
ADD ./requirements.yml .
ADD files ./files

RUN ansible-galaxy install -r requirements.yml -p roles --force-with-deps

RUN ansible-playbook -i localhost playbook.yml -v -e galaxy_root=$GALAXY_ROOT \
    -e galaxy_server_dir=$GALAXY_SERVER -e galaxy_venv_dir=$GALAXY_VENV \
    -e pip_extra_args="$PIP_EXTRA_ARGS" -e galaxy_commit_id=$GALAXY_COMMIT_ID \
    -e galaxy_mutable_data_dir=$GALAXY_DATA

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
        $GALAXY_SERVER/.ci \
        $GALAXY_SERVER/.git \
        $GALAXY_VENV/include/node \
        $GALAXY_VENV/src/node* \
        $GALAXY_SERVER/doc \
        $GALAXY_SERVER/test \
        $GALAXY_SERVER/test-data

# Clean up *all* node_modules, including plugins.  Everything is already built+staged.
RUN find $GALAXY_SERVER -name "node_modules" -type d -prune -exec rm -rf '{}' +

###############################################################################
# Stage 2
###############################################################################

FROM $BASE as stage2

ARG GALAXY_ROOT
ARG GALAXY_SERVER
ARG GALAXY_USER
ARG GALAXY_VENV
ARG GALAXY_DATA
# Init Env
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8

# Ensure a default sqlite database ends up in the galaxy_data directory.
ENV GALAXY_CONFIG_DATABASE_CONNECTION="sqlite:///$GALAXY_DATA/universe.sqlite?isolation_level=IMMEDIATE"

# Install python-virtualenv
RUN set -xe; \
    echo "Acquire::http {No-Cache=True;};" > /etc/apt/apt.conf.d/no-cache \
    && apt-get -qq update && apt-get install -y --no-install-recommends \
        locales \
        vim-tiny \
        nano-tiny \
        curl \
        python3-pip python3-setuptools python3-virtualenv libpython3.7 \
    && echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen \
    && locale-gen $LANG && update-locale LANG=$LANG \
    && apt-get autoremove -y && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/*

RUN set -xe; \
      adduser --system --group $GALAXY_USER \
      && mkdir -p $GALAXY_SERVER \
      && chown $GALAXY_USER:$GALAXY_USER $GALAXY_ROOT -R

WORKDIR $GALAXY_ROOT
# Copy galaxy files to final image
# The chown value MUST be hardcoded (see #35018 at github.com/moby/moby)
COPY --chown=galaxy:galaxy --from=stage1 $GALAXY_ROOT .

# Expose http and uwsgi socket
EXPOSE 8080
EXPOSE 3031
USER $GALAXY_USER

ENV PATH="$GALAXY_VENV/bin:${PATH}"

WORKDIR $GALAXY_SERVER
# [optional] to run:
CMD uwsgi --yaml /galaxy/config/galaxy.yml
