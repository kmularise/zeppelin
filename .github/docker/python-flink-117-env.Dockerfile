FROM continuumio/miniconda3:24.1.2-0

# Build argument for environment file path
ARG ENV_FILE=testing/env_python_3_with_flink_117.yml

# Metadata labels
LABEL org.opencontainers.image.source=https://github.com/apache/zeppelin
LABEL org.opencontainers.image.description="Zeppelin test environment with Python 3 and Flink 1.17"

# Copy environment file
COPY ${ENV_FILE} /tmp/environment.yml

# Create conda environment (optimized in one layer)
RUN conda env create -f /tmp/environment.yml && \
    conda clean -afy && \
    rm /tmp/environment.yml

# Install Java 11 for Maven
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openjdk-11-jdk \
        git \
        curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV PATH=/opt/conda/envs/python_3_with_flink/bin:$PATH \
    JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64 \
    CONDA_DEFAULT_ENV=python_3_with_flink

WORKDIR /workspace

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python --version && conda --version

CMD ["/bin/bash"]
