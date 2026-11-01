FROM node:22-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .

ARG VITE_API_URL=
ARG VITE_MODEL_NAME=Llama

ENV VITE_API_URL=$VITE_API_URL
ENV VITE_MODEL_NAME=$VITE_MODEL_NAME

RUN npm run build

FROM nginx:1.27-alpine

# Change Nginx PID location to a path writable by non-root users
RUN sed -i 's#pid .*;#pid /tmp/nginx.pid;#' /etc/nginx/nginx.conf

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

RUN addgroup -S web \
    && adduser -S web -G web \
    && chown -R web:web /usr/share/nginx/html /var/cache/nginx /var/run /var/log/nginx

USER web

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1