FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py ./
RUN chmod 0644 main.py

# Bake the model into the image so startup does not depend on Hugging Face.
ENV HF_HOME=/opt/hf
RUN python -c "from model2vec import StaticModel; StaticModel.from_pretrained('minishlab/potion-base-32M')" \
    && chmod -R a+rX /opt/hf

ENV PORT=8081
EXPOSE 8081

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
