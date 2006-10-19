/* Copyright (C) 2000-2002 SuSE Linux AG, Nuremberg.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2, or (at your option)
   any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software Foundation,
   Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.  */

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>

// ' '
#define END_CHAR	0

int
main (int argc, char *argv[])
{
  FILE *fp;
#define MAX_VERSION_LENGTH 1024
  char buffer[4096 + MAX_VERSION_LENGTH]; /* buffer + sizeof ("Linux version .....") */
  char command[512] = "";
  int found = 0;

  if (argc != 2)
    {
      char msg[] = "usage: get_kernel_version <kernel_image>\n";
      write (2, msg, sizeof (msg));
      return 1;
    }

  /* check if file exist and is compressed */
  {
    unsigned char  buf [2];
    int fd = open (argv[1], O_RDONLY);
    if (fd == -1)
      {
	fprintf (stderr, "Cannot open kernel image \"%s\"\n", argv[1]);
	return 1;
      }

    if (read (fd, buf, 2) != 2)
      {
	fprintf (stderr, "Short read\n");
	close (fd);
	return 1;
      }

    if (buf [0] == 037 && (buf [1] == 0213 || buf [1] == 0236))
      {
	snprintf (command, sizeof (command), "/bin/gzip -dc %s 2>/dev/null", argv[1]);
	fp = popen (command, "r");
	if (fp == NULL)
	  {
	    fprintf (stderr, "%s: faild\n", command);
	    return 1;
	  }
      }
    else
      {
	fp = fopen (argv[1],"r");
      }
    close (fd);
  }

  memset (buffer, 0, sizeof (buffer));


  while (!found)
    {
      ssize_t in;
      int i;

      in = fread (&buffer[MAX_VERSION_LENGTH],
		  1, sizeof (buffer) - MAX_VERSION_LENGTH, fp);

      if (in <= 0)
	break;
      for (i = 0; i < in; i++)
	if (buffer[i] == 'L' && buffer[i+1] == 'i' &&
	    buffer[i+2] == 'n' && buffer[i+3] == 'u' &&
	    buffer[i+4] == 'x' && buffer[i+5] == ' ' &&
	    buffer[i+6] == 'v' && buffer[i+7] == 'e' &&
	    buffer[i+8] == 'r' && buffer[i+9] == 's' &&
	    buffer[i+10] == 'i' && buffer[i+11] == 'o' &&
	    buffer[i+12] == 'n' && buffer[i+13] == ' ')
	  {
	    found = 1;
	    break;
	  }

      if (found)
	{
	  int j;
	  for (j = i+14; buffer[j] != END_CHAR; j++);
	  buffer[j] = '\0';
	  printf ("%s\n", &buffer[i+14]);
	}
      else
	{
	  if (in < (sizeof (buffer) - MAX_VERSION_LENGTH))
	    break;
	  memcpy (&buffer[0], &buffer[sizeof (buffer) - MAX_VERSION_LENGTH],
		  MAX_VERSION_LENGTH);
	  memset (&buffer[MAX_VERSION_LENGTH], 0,
		  sizeof (buffer) - MAX_VERSION_LENGTH);
	}
    }

  if(!found) {
    /* ia32 kernel */
    if(
      !fseek(fp, 0x202, SEEK_SET) &&
      fread(buffer, 1, 4, fp) == 4 &&
      buffer[0] == 0x48 && buffer[1] == 0x64 &&
      buffer[2] == 0x72 && buffer[3] == 0x53 &&
      !fseek(fp, 0x20e, SEEK_SET) &&
      fread(buffer, 1, 2, fp) == 2
    ) {
      unsigned ofs = 0x200 + ((unsigned char *) buffer)[0] + (((unsigned char *) buffer)[1] << 8);

      if(
        !fseek(fp, ofs, SEEK_SET) &&
        fread(buffer, 1, MAX_VERSION_LENGTH, fp) == MAX_VERSION_LENGTH
      ) {
        char *s = buffer;

        for(s[MAX_VERSION_LENGTH] = 0; *s; s++) if(*s == END_CHAR) { *s = 0; break; }
        if(*buffer) {
          found = 1;
          printf("%s\n", buffer);
        }
      }
    }
  }

  if (command[0] != '\0')
    pclose (fp);
  else
    fclose (fp);

  if (found)
    return 0;
  else
    return 1;

  return 0;
}
