# For more information, please refer to https://aka.ms/vscode-docker-python
FROM python:3.8-slim-buster

# Copy the source files into the container
WORKDIR /flask-docker
COPY . /flask-docker

# Install pip requirements
RUN pip3 install virtualenv
RUN python3 -m venv web-app 
RUN . web-app/bin/activate
RUN python3 -m pip install -r requirements.txt

EXPOSE 8080
ENV PORT 8080

# Define the command to be run when the container is started
CMD ["python", "main.py"]