@[out-extension: html @]@rem
@[import rwt_processor.html.minlit @]@rem
@[article-start: "A Python LitProg Weaver" 
                 "Richard Todd" 
                 "2011-02-22" @]

@* Overview.  I am a fan of Literate Programming, and since I'm writing papers
about various algorithms, I thought I might as well make the papers into 
executable code in the process! It seems most litprog enthusiasts roll their
own system, so I thought I might as well do the same.  

<p>I should note: the purpose of this document isn't to be an ideal
example of literate programming in action.  The weaving program is a
well-understood idea, and I'm not doing anything novel here.  
The goal was to get this tool written as quickly as possible, so that I could get on
to writing more interesting programs with it. 

@ First thing's first.  Let's define the overview 
of our program:

@<file:pyweave.py@>=
#!/usr/bin/env python

import sys
import rwt_processor.processor as fp 

@< Data Structures @>
@< Functions @>
@< Weave Formatters @>
@< Greet the user @>
@< Process the input file @>

@ Greeting the user should be easy enough.  Just give a version
number to make it look professional.

@<Greet...@>=
print('pyweave v0.2 '
      '(c) 2011 Richard Todd '
      '<richard@@richardtodd.name>')
print()

@ The biggest challenge for the weaver is 
getting all of the cross-references correct.  We'll have to process the 
entire input before writing out any output.    

@< Process the input file @>=
filename = sys.argv[1]

print('Reading',filename)

with fp.FileProcessor(open(filename,'r')) as infile:
    @<Register the out-extension command@>
    @<Gather up data about the input file@>

outfilename = filename[:filename.rindex('.')] + '.' + outExtension
print('Writing',outfilename)

with open(outfilename,'w') as outfile:
    @<Select the correct output style@>
    @<Write the output file @>

print('Done!')

@ The user should tell us what kind of file we are weaving.  In this version, 
plain text, LaTeX, and HTML are supported.
@<Register the out-extension...@>=
infile.register("out-extension",set_ext,False);

@<Functions@>=
outExtension = "txt"
def set_ext(processor,txt):
  global outExtension
  outExtension = txt

@* Reading in the Input.  We'll suck the input file into a data structure
line-by-line.  The structure of a web file is such that the document is 
composed of:
<ul>
<li> HTML prematter
<li> Alternating 'text' and 'code' sections
  <ul>
     <li> Bare text sections start with |@|
     <li> Named text sections start with |@*|
     <li> Raw HTML sections start wil |@+ | 
     <li> Code sections start with |@<name@>|=
  </ul>
</ul>
<p> We'll grab the prematter by inserting an assumed
raw HTML section at the top of the file...
@<Gather up data...@>=
line = "@+\n" # start with RAW html...
while True:
   if len(line) == 0:
       break
   elif is_text_head(line):
      line = process_text(infile,line)
   elif is_code_head(line):
      line = process_code(infile,line)
   else:
      raise SyntaxError("Unknown input: "+line)

@ The functions to spot text and code headings are
pretty straightforward.
@<Functions@>=
def is_text_head(line):
  return ( line.startswith('@ ') or
           line.startswith('@* ') or
           line.startswith('@+') or
           line.rstrip() == '@'
         )

def is_code_head(line):
    tmp = line.strip()
    return ( tmp.startswith('@<') and
             tmp.endswith('@>=') )

@ Now, when we process a text or code section, we'll need to put them
in a data structure that understands their alternating pattern and
interrelationships.  For starters, we'll need a name registry to track the
section numbers where we defined and used a given code section.  
@< Data Structures @>=
class name_entry:
  def __init__(self):
     self.defined = []
     self.used_in = []

name_registry = {}  # "name" -> name_entry

@ We also need to store off the actual words used in the input file, for both
the text and the code sections.
@< Data Structures @>=
class input_pair:
  def __init__(self):
     self.number = None
     self.text = []
     self.text_name = None
     self.code = []
     self.code_name = None

input_db = []     # list of input_pairs

@ We'll make a convenience function to grab a new section number.
@<Functions@>=
def gen_new_section(): 
  num = 1
  while True:
    yield num
    num = num + 1

section_number = gen_new_section()

@ The code for text sections is pretty straightforward.  Since text sections always
precede code sections, this is the place where new |input_pair|s are added to our
list.
@<Functions@>=
def process_text(infile,line):
   new_section = input_pair()
   if line.startswith('@*'):
      line = line[3:].lstrip()
      new_section.text_name = line[:line.index('.')+1]
      line = line[line.index('.')+1:]
      new_section.number = next(section_number)
   elif line.startswith('@+'):
      line = line[3:].lstrip()
   else:
      line = line[1:]
      new_section.number = next(section_number)
   if len(line.strip())>0: 
     new_section.text.append(line)
   num_empty = 0
   while True:
        line = infile.readline()
        if ( len(line) == 0 or
             is_text_head(line) or
             is_code_head(line)  ):
           break
        elif len(line.strip())>0:
           if num_empty > 0:
              if len(new_section.text) > 0:
                 new_section.text.append('\n'*num_empty)
           num_empty = 0
           new_section.text.append(line)
        else:
           num_empty = num_empty + 1
   input_db.append(new_section)
   return line

@ When we encounter a named code section, we'll need to be able to
convert names like "abbrev..." to "abbreviated name" by looking it
up in the name registry.  This is a strict linear search, so the
algorithm would need to be improved if we ever want to handle huge
inputs efficiently.

@<Functions@>=
def normalize_name(name):
    tmp = name.strip()
    if tmp.endswith('...'):
        found = None
        tmp = tmp[:-3]
        for k in name_registry:
            if k.startswith(tmp):
                if not found:
                    found = k
                else:
                    raise ValueError(name + 
                                     " matches both <" + 
                                     found + "> and <" + 
                                     k + ">")
        if found:
            tmp = found
        else:
            raise ValueError(name + " does not match any " +
                             "code sections defined so far!")
    return tmp

@ Now, with the ability to look up abbreviations, we can process a code section.  
We track cross reference information as we go.

@<Functions@>=
def process_code(infile,line):
    @<Create a new |input_pair| if necessary@>
    @<Add the definition to our registry@>
    answer = []
    num_empty = 0
    while True:
        rawline = infile.readline()
        line = rawline.rstrip()
        if (len(rawline) == 0 or 
            is_text_head(rawline) or
            is_code_head(rawline) ):
            break
        elif  len(line)==0:
            num_empty = num_empty+1
        else: 
            if num_empty > 0:
               answer.append('\n'*num_empty)
               num_empty = 0
            answer.append(line+'\n')
            if is_code_pointer(line):
                @<Remember where this code was used@>
    @<Store the code in the input database@>
    return rawline

@ We grab the most recent |input_pair|, checking to
make sure that it has a section number <em>and</em> doesn't
already have code in it.  If it does, we make a new
|input_pair| with a section number, but devoid of text.  At
the end of this code, |pair| points to the |input_pair| to which 
we'll be adding.
@<Create a new |input_pair| if necessary@>=
pair = None 
if len(input_db) > 0:
  pair = input_db[-1]
else:
  pair = input_pair()

if( (pair.number == None) or
    (pair.code_name != None) ):
  pair = input_pair()
  pair.number = next(section_number)
  input_db.append(pair)

@
@<Add the definition to our registry@>=
code_name = normalize_name(line.strip()[2:-3])
entry = name_registry.setdefault(code_name,name_entry())
entry.defined.append(pair.number)

@
@<Remember where this code was used@>=
pointed_name = extract_code_pointer(line)
pointed = name_registry.setdefault(pointed_name,name_entry())
pointed.used_in.append(pair.number)

@
@<Store the code in the input database@>=
pair.code = answer
pair.code_name = code_name

@
@<Functions@>=
def is_code_pointer(line):
    tmp = line.strip()
    return ( tmp.startswith('@<') and
             tmp.endswith('@>') )
def extract_code_pointer(line):
    return normalize_name(line.strip()[2:-2])

@* Output. Ok, now that we've read in the file and gotten all of the cross references
worked out, we simply need to output our woven file.  This is pretty easy to
do... we just need to select the right formatter and push all the data through it.

@ Yeah, I know I should make a fancy factory or something, but there's only
four choices at the moment... deal with it!
@<Select the correct output style@>=
formatter = None 
if outExtension == "txt":
  formatter = TextWeaver(outfile)
elif outExtension == "tex":
  formatter = LaTeXWeaver(outfile)
elif outExtension == "html":
  formatter = HTMLWeaver(outfile)
elif outExtension == "bbcode":
  formatter = BBCodeWeaver(outfile)

@<Write the out...@>=
for entry in input_db:
   @<Output a text+code pair@>

@ Though the code here is long, it is also pretty straightforward. 
We print out the section, including its name if it has one, in bold.  Then
we print any text it has.  Then, we output the code associated with this
section. 

@<Output a text+code...@>=
formatter.nextEntry()
if (entry.number != None):
  formatter.entryNumber(entry.number,entry.text_name)
for l in entry.text:
   process_code_escapes(formatter,l)
if entry.code_name:
   @<Output a code header@> 
   formatter.startCodeBlock()
   for l in entry.code:
      if is_code_pointer(l):
         @<Output a code pointer@>
      else:
         formatter.code(l)
   formatter.endCodeBlock()
   @<Output a code footer@>

@ The textual portion can escape to |code| mode by enclosing some
text in vertical bars like this: &#124;|code|&#124;.  If you want to
use a single vertical bar (<em>as a vertical bar</em>) in a line of 
text, that's fine... and you can even put two next to each other without
worrying.  If you want two on a line with any text in between, though, 
you'll need to escape them in some way (i.e. in HTML text you can 
use the HTML entity &amp;124;).

@<Functions@>=
def process_code_escapes(formatter,s):
  ind1 = s.find('|')
  if(ind1 >= 0):
     ind2 = s.find('|', ind1+1)
     if(ind2 > 0):
        if (ind2-ind1) > 1:
          formatter.text(s[:ind1])
          formatter.inlineCode(s[ind1+1:ind2])
        else:
          formatter.text(s[:ind2+1])
        process_code_escapes(formatter,s[ind2+1:])
     else:
        formatter.text(s)  
  else:
    formatter.text(s)

@ To output a proper-looking code heading, we need to look it up
in the name registry, and find out if this is the first definition
of it, or not.  Most everything else is handled in the formatter.
@<Output a code header@>=
reg_ent = name_registry[entry.code_name]
formatter.codeHeader(entry.code_name,
                     reg_ent.defined[0] != entry.number, 
                     len(entry.text) > 0)


@ Outputting a code pointer involves looking up its number,
escaping out of <code>code</code>-mode for this line. 
@<Output a code pointer@>=
pname = extract_code_pointer(l)
formatter.codePointer(pname,name_registry[pname].defined[0],len(l)-len(l.lstrip()))


@ The code footer consists of a "see also" section (which tells us 
which other paragraphs include further definition of this code fragment),
and a "used in" section (which tells us where this code was used).
@<Output a code footer@>=
seealso = [e for e in reg_ent.defined if e != entry.number]
if len(seealso)>0: 
  formatter.seeAlso(seealso)

if len(reg_ent.used_in)>0:
  formatter.usedIn(reg_ent.used_in)

@<Weave Formatters@>=
class HTMLWeaver:
  def __init__(self,of):
     self.__outfile = of

  def __make_section_anchor(self,sec):
    return '<a name="sect{0}">{0}</a>'.format(sec)
  def __make_section_link(self,sec):
    return '<a href="#sect{0}">{0}</a>'.format(sec)
  def __sanitize_for_HTML(self,s):
    return s.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')

  def nextEntry(self):
    print('<p>',end='',file=self.__outfile)

  def entryNumber(self,num,name):
    print('<strong>{0}. {1}</strong>'.format(
                                          self.__make_section_anchor(num),
                                          name or ''),
          sep = '',end = '',file = self.__outfile)

  def text(self,l):
    self.__outfile.write(l)

  def inlineCode(self,l):
    print('<code>',l,'</code>',sep='',end='',file=self.__outfile)

  def codeHeader(self,name,continued,afterText):
    suffix = ' &rang;&equiv;'
    if continued:
         suffix = ' &rang;+&equiv;'
    prefix='';
    if afterText:
       prefix = '<p>'
    print(prefix,'&lang;',end='',file=self.__outfile)
    process_code_escapes(self,name)
    print(suffix,file = self.__outfile)

  def startCodeBlock(self):
    print('<pre class=listing><code>',end='',file = self.__outfile)

  def endCodeBlock(self):
    print('</code></pre>',file = self.__outfile)

  def codePointer(self,name,number,wspace):
    self.__outfile.write(' '*wspace)
    print('</code>&lt; ',end='',file=self.__outfile)
    process_code_escapes(self,name)
    print(' ',self.__make_section_link(number),' &gt;<code>',sep='',file = self.__outfile)

  def code(self, l):
    self.__outfile.write(self.__sanitize_for_HTML(l))
  
  def seeAlso(self, sa):
     seealso = map(self.__make_section_link,sa)
     print('<br>See also: ',end = '',file = outfile)
     print(*seealso,sep = ', ',end = '',file = outfile)
     print('.',file=outfile)

  def usedIn(self, ui):
     usedin = map(self.__make_section_link,ui)
     print('<br>This code used in: ',end = '',file = outfile)
     print(*usedin,sep = ', ',end = '',file = outfile)
     print('.',file=outfile)

@<Weave Formatters@>=
class TextWeaver:
  def __init__(self,of):
     self.__outfile = of

  def nextEntry(self):
    print('\n\n',end='',file=self.__outfile)

  def entryNumber(self,num,name):
    print('{0}. {1}'.format(num,name or ''),
          sep = '',end = '',file = self.__outfile)

  def text(self,l):
    self.__outfile.write(l)

  def inlineCode(self,l):
    print('|',l,'|',sep='',end='',file=self.__outfile)

  def codeHeader(self,name,continued,afterText):
    if afterText:
      print('',file=self.__outfile)
      print('   < ',end='',file=self.__outfile)
    else:
      print('< ',end='',file=self.__outfile)
    process_code_escapes(self,name)
    if continued:
      print(' >+=',file=self.__outfile)
    else:
      print(' >=',file=self.__outfile)

  def startCodeBlock(self):
    pass

  def endCodeBlock(self):
    print('',file=self.__outfile) 

  def codePointer(self,name,number,wspace):
    self.__outfile.write(' '*(wspace+4))
    self.__outfile.write('<')
    process_code_escapes(self,name)
    print(' ',number,'>',sep='',file = self.__outfile)

  def code(self, l):
    self.__outfile.write('    ')
    self.__outfile.write(l)
  
  def seeAlso(self, sa):
     print('See also: ',end = '',file = outfile)
     print(*sa,sep = ', ',end = '',file = outfile)
     print('.',file=outfile)

  def usedIn(self, ui):
     print('This code used in: ',end = '',file = outfile)
     print(*ui,sep = ', ',end = '',file = outfile)
     print('.',file=outfile)

@<Weave Formatters@>=
class LaTeXWeaver:
  def __init__(self,of):
     self.__outfile = of
     self.__inlineCharOpts = '!@$,*:abcdefghijklmnopqrstuvwxyz'
     self.__inCode = False

  def __sanitizeCode(self, c):
    #return c.replace('|','|\\textbar|') 
    return c.replace('%','%\char37%')

  def nextEntry(self):
    print('\n\n',end='',file=self.__outfile)

  def entryNumber(self,num,name):
    print('\\bigbreak\\noindent{{\\bfseries {0}. {1}}}'.format(num,name or ''),
          sep = '',end = '',file = self.__outfile)

  def text(self,l):
    self.__outfile.write(l)

  def inlineCode(self,l):
    if self.__inCode:
       # Can't do much already inside a listing...except break back into
       # listing mode...
       print('}%',l,'%\\textrm{',sep='',end='',file=self.__outfile)
    else:
       # select a character not in the string
       goodopts = (c for c in self.__inlineCharOpts if l.find(c) < 0)
       cch = next(goodopts) 
       print('\\lstinline',cch,l,cch,sep='',end='',file=self.__outfile)

  def codeHeader(self,name,continued,afterText):
    if afterText:
      print('',file=self.__outfile)
      print('\\noindent$<$ ',end='',file=self.__outfile)
    else:
      print('$<$ ',end='',file=self.__outfile)
    process_code_escapes(self,name)
    if continued:
      print(' $>+\\equiv$',file=self.__outfile)
    else:
      print(' $>\\equiv$',file=self.__outfile)

  def startCodeBlock(self):
    print('\\begin{lstlisting}',file=self.__outfile)
    self.__inCode = True

  def endCodeBlock(self):
    print('\\end{lstlisting}',file=self.__outfile) 
    self.__inCode = False

  def codePointer(self,name,number,wspace):
    self.__outfile.write(' '*(wspace+2))
    self.__outfile.write('%\\textrm{$<$')
    process_code_escapes(self,name)
    print(' ',number,'$>$}%',sep='',file = self.__outfile)

  def code(self, l):
    self.__outfile.write('  ')
    self.__outfile.write(self.__sanitizeCode(l))
  
  def seeAlso(self, sa):
     print('See also: ',end = '',file = outfile)
     print(*sa,sep = ', ',end = '',file = outfile)
     print('.\\\\',file=outfile)

  def usedIn(self, ui):
     print('This code used in: ',end = '',file = outfile)
     print(*ui,sep = ', ',end = '',file = outfile)
     print('.',file=outfile)

@<Weave Formatters@>=
class BBCodeWeaver:
  def __init__(self,of):
     self.__outfile = of

  def nextEntry(self):
    print('\n\n',end='',file=self.__outfile)

  def entryNumber(self,num,name):
    print('[b]{0}. {1}[/b]'.format(num,name or ''),
          sep = '',end = '',file = self.__outfile)

  def text(self,l):
    self.__outfile.write(l)

  def inlineCode(self,l):
    print('[color=green]',l,'[/color]',sep='',end='',file=self.__outfile)

  def codeHeader(self,name,continued,afterText):
    if afterText:
      print('',file=self.__outfile)
      print('[color=green]< ',end='',file=self.__outfile)
    else:
      print('[color=green]< ',end='',file=self.__outfile)
    process_code_escapes(self,name)
    if continued:
      print(' >+=[/color]',file=self.__outfile)
    else:
      print(' >=[/color]',file=self.__outfile)

  def startCodeBlock(self):
    print('[code]',file=self.__outfile)

  def endCodeBlock(self):
    print('[/code]\n',file=self.__outfile) 

  def codePointer(self,name,number,wspace):
    self.__outfile.write(' '*wspace)
    self.__outfile.write('<')
    process_code_escapes(self,name)
    print(' ',number,'>',sep='',file = self.__outfile)

  def code(self, l):
    self.__outfile.write(l)
  
  def seeAlso(self, sa):
     print('[i]See also: ',end = '',file = outfile)
     print(*sa,sep = ', ',end = '',file = outfile)
     print('.[/i]',file=outfile)

  def usedIn(self, ui):
     print('[i]This code used in: ',end = '',file = outfile)
     print(*ui,sep = ', ',end = '',file = outfile)
     print('.[/i]',file=outfile)


@+
@article-end
