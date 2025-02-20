# ironcore-in-a-box

[![REUSE status](https://api.reuse.software/badge/github.com/ironcore-dev/ironcore-in-a-box)](https://api.reuse.software/info/github.com/ironcore-dev/ironcore-in-a-box)
[![GitHub License](https://img.shields.io/static/v1?label=License&message=Apache-2.0&color=blue)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://makeapullrequest.com)

<p align="center">
  <img src="docs/assets/logo.png" alt="IronCore in a Box" width="300"/>
</p>

## Overview

**IronCore in a Box** is a project that brings up the IronCore stack inside a local [`kind`](https://kind.sigs.k8s.io/) cluster. It provides a local demo environment to illustrate the capabilities of IronCore.

## Prerequisites

Ensure you have the following installed before running the project:
- [`make`](https://www.gnu.org/software/make/)
- [`go`](https://go.dev/)
- [`docker`](https://www.docker.com/)

## Installation

To set up and start the IronCore stack, run:
```sh
make up
```

This will create a local `kind` cluster and deploy the IronCore stack.

## Cleanup

To remove everything, run:
```sh
make down
```

This will delete the `kind` cluster and clean up any resources.

## License

[Apache-2.0](LICENSE)


