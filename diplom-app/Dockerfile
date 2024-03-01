FROM python:3.9.18
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE 1

RUN pip install --no-cache-dir --upgrade pip
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY webapp /webapp
RUN chmod -R 777 /webapp
WORKDIR /webapp

EXPOSE 8000

CMD ["gunicorn", "-c", "gunicorn.py", "webapp.wsgi:application"]