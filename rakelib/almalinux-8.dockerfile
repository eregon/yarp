FROM almalinux:8
RUN dnf install -y make gcc ruby
ADD . /prism
WORKDIR /prism
RUN make
