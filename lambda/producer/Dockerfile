FROM python:3.9-slim

RUN apt-get update && apt-get install -y zip

WORKDIR /app
COPY requirements.txt .
RUN pip install --target /package -r requirements.txt

COPY src/ /package/

WORKDIR /package
RUN zip -r /lambda_function.zip .