################## BASE IMAGE ######################

FROM clinicalgenomics/mip:latest

################## METADATA ######################

LABEL base_image="clinicalgenomics/mip:latest"
LABEL version="1"
LABEL software="manta"
LABEL software.version="1.6.0"
LABEL extra.binaries="configManta.py"

################## MAINTAINER ######################
MAINTAINER Clinical-Genomics/MIP

RUN conda install python=2.7 manta=1.6.0=py27_0

## Creating symbolic links for conda packages
RUN ln --symbolic --force /opt/conda/share/manta-1.6.0-0/bin/configManta.py.ini /opt/conda/bin/configManta.py.ini
RUN ln --symbolic --force /opt/conda/share/manta-1.6.0-0/bin/configManta.py /opt/conda/bin/configManta.py

## Clean up after conda
RUN /opt/conda/bin/conda clean -tipsy

WORKDIR /data/
