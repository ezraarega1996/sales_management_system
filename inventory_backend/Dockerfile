# Use the official Node.js image as the base image
FROM node:20

# Set the working directory
WORKDIR /app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install dependencies
RUN npm install
RUN npm install -g nodemon

# Copy the rest of the application source code
COPY . .

# Expose the port your server listens on (change if needed)
EXPOSE 5000

# Start the server (update the path if your entrypoint is different)
CMD ["nodemon", "server.js"]
