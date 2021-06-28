#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include <signal.h>

#define MAX_CLIENTS 25
#define MAX_LINE 1024

typedef struct _User {
  int socket;
  char nickname[MAX_LINE];
} User;

int sockServer;
User users[MAX_CLIENTS];

pthread_mutex_t mutex;

void *child(void *arg);

void error(char *msg);

void handler(int sig);

int main(int argc, char **argv) {
  int *soclient, i = 0;
  struct sockaddr_in servidor, clientedir;
  socklen_t clientelen;
  pthread_t thread;
  pthread_attr_t attr;

  if (argc <= 1) error("Faltan argumentos");

  if ((sockServer = socket(AF_INET, SOCK_STREAM, 0)) < 0 )
    error("Socket Init");

  servidor.sin_family = AF_INET; 
  servidor.sin_addr.s_addr = INADDR_ANY; 
  servidor.sin_port = htons(atoi(argv[1]));

  if (bind(sockServer, (struct sockaddr *) &servidor, sizeof(servidor)))
    error("Error en el bind");

  printf("Binding successful, and listening on %s\n",argv[1]);

  pthread_attr_init(&attr);
  pthread_attr_setdetachstate(&attr,PTHREAD_CREATE_DETACHED);

  pthread_mutex_init(&mutex, NULL);

  signal(SIGINT, handler);

  for (; i < MAX_CLIENTS; ++i)
    users[i].socket = -1;

  if (listen(sockServer, MAX_CLIENTS) == -1)
    error(" Listen error ");

  for (;;) {
    soclient = malloc(sizeof(int));

    clientelen = sizeof(clientedir);
    if ((*soclient = accept(sockServer
                          , (struct sockaddr *) &clientedir
                          , &clientelen)) == -1)
      error("No se puedo aceptar la conexión. ");

    pthread_create(&thread , NULL , child, (void *) soclient);
  }

  close(sockServer);
  return 0;
}

void* child(void *_arg) {
  int socket = *(int*) _arg, i = 0, flag = 0, myId;
  char buf[MAX_LINE] = "", msg[MAX_LINE*2] = "", nickname[MAX_LINE] = "", aux[MAX_LINE*2] = "";

  while (!flag) {
    send(socket, "INGRESE UN NICKNAME:", sizeof("INGRESE UN NICKNAME:"), 0);
    recv(socket, buf, sizeof(buf), 0);
    if (!strcmp(buf, "/exit"))
      break;
    if (strchr(buf, ' ') == NULL && buf[0]!='/') {
      pthread_mutex_lock(&mutex);
      for (i = 0; i < MAX_CLIENTS; ++i) {
        if (users[i].socket != -1 && !strcmp(buf, users[i].nickname)) {
          send(socket, "NICKNAME YA EN USO", sizeof("NICKNAME YA EN USO"), 0);
          break;
        }
      }
      if (i == MAX_CLIENTS) {
        flag = 1;
        for (i = 0; i < MAX_CLIENTS; ++i) {
          if (users[i].socket == -1) {
            users[i].socket = socket;
            strcpy(users[i].nickname, buf);
            break;
          }
        }
      }
      pthread_mutex_unlock(&mutex);
    } else
      send(socket, "NICKNAME INVALIDO", sizeof("NICKNAME INVALIDO"), 0);
  }

  if (!flag) {
    free((int*)_arg);
    return NULL;
  }

  myId = i;

  strcpy(msg, users[myId].nickname);
  strcat(msg, " ENTRO A LA SALA");
  msg[strlen(msg)] ='\0';
  send(socket, "USUARIOS CONECTADOS:", sizeof("USUARIOS CONECTADOS:"), 0);
  pthread_mutex_lock(&mutex);
  for (i = 0; i < MAX_CLIENTS; ++i) {
    if (i != myId && users[i].socket != -1) {
      send(users[i].socket, msg, sizeof(msg), 0);
      send(socket, users[i].nickname, sizeof(users[i].nickname), 0);
    }
  }
  pthread_mutex_unlock(&mutex);
  
  send(socket, "BENVINDO", sizeof("BENVINDO"), 0);
  for (;;) {
    strcpy(nickname, "");
    strcpy(msg, "");
    strcpy(aux, "");
    recv(socket, buf, sizeof(buf), 0);
    printf("soy %d [%s] en socket %d--> Recv: %s\n", myId, users[myId].nickname, socket, buf);

    if (buf[0] != '/') {
      strcpy(msg, users[myId].nickname);
      strcat(msg, ": ");
      strcat(msg, buf);
      msg[strlen(msg)] ='\0';
      pthread_mutex_lock(&mutex);
      for (i = 0; i < MAX_CLIENTS; ++i) {
        if (i != myId && users[i].socket != -1) 
          send(users[i].socket, msg, sizeof(msg), 0);
      }
      pthread_mutex_unlock(&mutex);
    } else {
      if (!strcmp(buf, "/exit"))
        break;
      if (strlen(buf) > 10 && buf[9] == ' ' && sscanf(buf, "/nickname %s", nickname) == 1) {
        if (strcmp(users[myId].nickname, nickname)) {
          if (strchr(nickname, ' ') == NULL && nickname[0]!='/') {
            pthread_mutex_lock(&mutex);
            for (i = 0; i < MAX_CLIENTS; ++i) {
              if (users[i].socket != -1 && !strcmp(nickname, users[i].nickname)) {
                send(socket, "NICKNAME YA EN USO", sizeof("NICKNAME YA EN USO"), 0);
                break;
              }
            }
            if (i == MAX_CLIENTS) {
              strcpy(msg, users[myId].nickname);
              strcat(msg, " CAMBIO SU NICKNAME A ");
              strcat(msg, nickname);
              msg[strlen(msg)] ='\0';
              for (i = 0; i < MAX_CLIENTS; ++i) {
                if (i != myId && users[i].socket != -1) 
                  send(users[i].socket, msg, sizeof(msg), 0);
              }
              strcpy(users[myId].nickname, nickname);
              send(socket, "NICKNAME ACTUALIZADO", sizeof("NICKNAME ACTUALIZADO"), 0);
            }
            pthread_mutex_unlock(&mutex);
          } else 
            send(socket, "NICKNAME INVALIDO", sizeof("NICKNAME INVALIDO"), 0);
        } else
          send(socket, "NO SE PUEDE CAMBIAR AL NICKNAME ACTUAL", sizeof("NO SE PUEDE CAMBIAR AL NICKNAME ACTUAL"), 0);
      } else if (strlen(buf) > 7 && buf[4] == ' ' && sscanf(buf, "/msg %s %[^\n]", nickname, msg) == 2) {
        strcpy(aux, users[myId].nickname);
        strcat(aux, " TE SUSURRO ");
        strcat(aux, msg);
        pthread_mutex_lock(&mutex);
        for (i = 0; i < MAX_CLIENTS; ++i) {
          if (users[i].socket != -1 && strcmp(nickname, users[i].nickname) == 0) {
            send(users[i].socket, aux, sizeof(aux), 0);
            break;
          }
        }
        if (i == MAX_CLIENTS)
          send(socket, "NICKNAME NO ENCONTRADO", sizeof("NICKNAME NO ENCONTRADO"), 0);
        pthread_mutex_unlock(&mutex);
      } else
        send(socket, "COMANDO INVALIDO", sizeof("COMANDO INVALIDO"), 0);
    }
  }

  strcpy(msg, users[myId].nickname);
  strcat(msg, " SE FUE DE LA SALA");
  msg[strlen(msg)] ='\0';
  pthread_mutex_lock(&mutex);
  for (i = 0; i < MAX_CLIENTS; ++i) {
    if (i != myId && users[i].socket != -1) 
      send(users[i].socket, msg, sizeof(msg), 0);
  }
  users[myId].socket = -1;
  pthread_mutex_unlock(&mutex);
  free((int*)_arg);
  return NULL;
}

void error(char *msg){
  exit((perror(msg), 1));
}

void handler(int sig) {
  int i = 0;
  pthread_mutex_lock(&mutex);
  for (; i < MAX_CLIENTS; ++i) {
    if (users[i].socket != -1)
      send(users[i].socket, "/server closed", sizeof("/server closed"), 0);
  }
  pthread_mutex_unlock(&mutex);
  
  close(sockServer);
  exit(EXIT_SUCCESS);
}
