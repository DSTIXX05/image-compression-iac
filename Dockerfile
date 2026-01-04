FROM public.ecr.aws/lambda/python:3.10

RUN yum install -y zip

RUN pip install Pillow -t "${LAMBDA_TASK_ROOT}/python/lib/python3.10/site-packages/"

RUN cd ${LAMBDA_TASK_ROOT} && zip -r /tmp/pillow-layer.zip python/