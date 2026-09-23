FROM node:24-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts
COPY src ./src
USER node
ENV DOZYCAT_SIGNAL_HOST=0.0.0.0 PORT=8787
EXPOSE 8787
CMD ["node", "src/main.mjs"]
