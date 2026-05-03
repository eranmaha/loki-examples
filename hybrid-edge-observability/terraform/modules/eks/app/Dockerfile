FROM public.ecr.aws/docker/library/node:24-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY index.js ./
USER node
EXPOSE 8080
CMD ["node", "index.js"]
