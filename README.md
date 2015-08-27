## Realtime Cloud Messaging Lua SDK
Part of the [The Realtime® Framework](http://framework.realtime.co), Realtime Cloud Messaging (aka ORTC) is a secure, fast and highly scalable cloud-hosted Pub/Sub real-time message broker for web and mobile apps.

If your application has data that needs to be updated in the user’s interface as it changes (e.g. real-time stock quotes or ever changing social news feed) Realtime Cloud Messaging is the reliable, easy, unbelievably fast, “works everywhere” solution.

##Linux install

`apt-get install lua5.1 liblua5.1-socket-dev liblua5.1-socket2 luasocket lua5.1-filesystem`

## Packing the project files into a single file

About Squish:
[http://matthewwild.co.uk/projects/squish](http://matthewwild.co.uk/projects/squish)

`squish squish-0.2.0/ --uglify --uglify-level=full`

## The Lua sample app
This sample in the app folder uses the Realtime® Framework Pub/Sub Lua library to connect, send and receive messages through a Realtime® Server in the cloud.

> NOTE: For simplicity these samples assume you're using a Realtime® Framework developers' application key with the authentication service disabled (every connection will have permission to publish and subscribe to any channel). For security guidelines please refer to the [Security Guide](http://messaging-public.realtime.co/documentation/starting-guide/security.html). 
> 
> **Don't forget to replace `YOUR_APPLICATION_KEY` and `YOUR_APPLICATION_PRIVATE_KEY` with your own application key. If you don't already own a free Realtime® Framework application key, [get one now](https://app.realtime.co/developers/getlicense).**


## API Reference
[http://messaging-public.realtime.co/documentation/lua/2.1.0/files/source/OrtcClient.html](http://messaging-public.realtime.co/documentation/lua/2.1.0/files/source/OrtcClient.html)


## Authors
Realtime.co
