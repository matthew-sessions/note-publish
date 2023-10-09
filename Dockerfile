FROM node:18-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

COPY . .
RUN  npm install --force
RUN npm run build

CMD ["npm", "start"]