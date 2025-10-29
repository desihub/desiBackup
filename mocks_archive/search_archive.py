#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path
import os
import numpy as np

def parse_file_to_dict(file_path,ftype='large'):
    """
    Parse a file containing multiple dictionaries into a single dictionary with lists.
    Handles concatenated dictionaries (}{) and missing keys (fills with None).

    Args:
        file_path (str): Path to the file to parse

    Returns:
        dict: Dictionary where each key maps to a list of values from all input dictionaries
    """
    # Initialize result dictionary
    result = {}

    # Variables to track current dictionary being parsed
    current_dict = {}
    current_key = None
    current_text = ""

    def process_dictionary(dict_text,ndic,ftype='large'):
        """Helper function to process a single dictionary text"""
        dict_data = {}
        lines = dict_text.strip("{}").split("\n")

        dict_data=json.loads(dict_text)
        if(ftype=='large'):
            #print(dict_data.keys())
            result[dict_data['path']]=dict_data
        elif(ftype=='split'):
            result[dict_data['original_file']]=dict_data

        return result


        for tkey in dict_data.keys():
            if tkey not in result:
                if(ndic==0):
                    result[tkey] = []
                else:
                    #This is because so far this key was not available
                    result[tkey] = [None]*ndic

        # Add values to result, using None for missing keys
        for key in result.keys():
            if key in dict_data:
                result[key].append(dict_data[key])
            else:
                result[key].append(None)

    with open(file_path, 'r') as file:
        text = file.read()
               # Handle case where dictionaries are concatenated with }{
        text = text.replace("}{", "}\n{")

        # Split into individual dictionaries
        dict_texts = text.split("\n{")
        for i, dict_text in enumerate(dict_texts):
            if i > 0:
                dict_text = "{" + dict_text
            if dict_text.strip():
                process_dictionary(dict_text,i,ftype=ftype)

    return result



def search_archives(pattern: str, file_dic):

    matches = []
    regex = re.compile(pattern)

    for file_path, archive_info in file_dic.items():
        if regex.search(file_path):
            matches.append((file_path, archive_info))

    return matches

def main():
    parser = argparse.ArgumentParser(description='''Search archived files:
        you should first extract the docs.tar with htar -xvf {archive_dir}/docs.tar and then give the path to this directory as --docs_dir
        example: python search_archive.py "ic_dens_N576_AbacusSummit_base_c000_ph000_" --docs_dir docs/ 
        To find all files in a directory:
        example: python search_archive.py "CutSky/LRG/z0.800/" --docs_dir docs/ ''',
                                     formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument('pattern', help='File pattern to search for, If you want to find all files within a folder then please use relative path, that is path from the main directory archived to find all files otherwise only a subset of files might be detcted.')
    parser.add_argument('--docs_dir', default='docs/',help='Give the path to the docs directory extracted from archive')
    
    args = parser.parse_args()
    
    #search file index
    file_index=f"{args.docs_dir}/file_index.json"
    with open(file_index, 'r') as f:
        file_index_dic = json.load(f)
    matches = search_archives(args.pattern, file_index_dic)
    
    #only load the split file
    split_file=f"{args.docs_dir}/split_file.json"
    if(os.path.isfile(split_file)):
        split_dic=parse_file_to_dict(split_file,ftype='split')
    else:
        split_dic={}

    #if large file exists then search in large dic
    # search large path file
    large_path_file=f"{args.docs_dir}/large_path_file.json"
    if(os.path.isfile(large_path_file)):
        large_dic=parse_file_to_dict(large_path_file,ftype='large')
        match_large=search_archives(args.pattern, large_dic)
        if match_large:
            ii=0
            for file_path, archive_info in match_large:
                #first check in the split file
                tmp_match_split=search_archives(match_large[ii][1]['short_path'], split_dic)
                fname=match_large[ii][1]['short_path'].split('/')[-1]
                if( tmp_match_split): #This means this is also big file and had to be split
                    #now look at the split file
                    tmp_match= search_archives(fname,file_index_dic)
                    match_large[ii][1]['archive']={'split_dic':tmp_match_split[0],'split_files':tmp_match}
                else:
                    match_large[ii][1]['archive'] = search_archives(fname , file_index_dic)
                ii=ii+1
    else:
        match_large=[]
        
    #if split file exists then search in split dic
    # search split file
    split_file=f"{args.docs_dir}/split_file.json"
    if(os.path.isfile(split_file)):
        match_split=search_archives(args.pattern, split_dic)
        if match_split:
            ii=0
            for file_path, archive_info in match_split:
                tsplit_file=match_split[ii][1]['split_files']
                for tt,tfile in enumerate(tsplit_file):
                    fname=tfile.split('/')[-1]
                    match_split[ii][1]['archive%d'%tt] = search_archives(fname, file_index_dic)
                ii=ii+1
    else:
        match_split=[]


    nmatch=np.array([len(matches),len(match_large),len(match_split)])
    
    if nmatch.sum()==0:                                                                     
        print(f"No files found matching pattern: {args.pattern}")
        return
    else:
        all_comms_dic=[]
        print(f"Found {nmatch.sum()} matching files: (regular:{nmatch[0]}, large: {nmatch[1]}, split: {nmatch[2]})")
        if(nmatch[0]>0):
            comms_dic=print_matches(matches,ftype='regular')
            all_comms_dic.append(comms_dic)
        
        if(nmatch[1]>0):
            comms_dic=print_matches(match_large,ftype='large')
            all_comms_dic.append(comms_dic)
        
        if(nmatch[2]>0):
            comms_dic=print_matches(match_split,ftype='split')
            all_comms_dic.append(comms_dic)

        print_commands_extract(all_comms_dic,outfile='extract_comms.sh')
            
    return 

def print_matches(matches,ftype='regular'):
    tag_dic={'regular': 'File:',
             'large': 'File (large path):',
             'split': 'File (split_files):'
             }
    comms_dic={'regular':[],'large_split':[],'large':[],'split':[]}
    for file_path, archive_info in matches:
        print(f"\n{tag_dic[ftype]} {file_path}")
        #print('\n\n',archive_info)
#        print('\n\n',archive_info['archive']['split_dic'][1])
        if(ftype=='regular'):
            print(f"Archive: {archive_info['archive']}")
            comms_dic['regular'].append(generate_extract_command(archive_info['archive'],file_path))
        elif(ftype=='large'):
            comm_this=[]
            print('\t This file has large file_path, given below is shorten_path')
            print(f"\t short_path: {archive_info['short_path']}")
            if('split_dic' in archive_info['archive']):
                sub_file_list=''
                print(f"\t\t This file was split in {archive_info['archive']['split_dic'][1]['num_chunks']} subfiles due to its size")
                for tfile_path, tinfo in archive_info['archive']['split_files']:
                    print(f"\t\t sub_File: {tfile_path}")
                    print(f"\t\t Archive: {tinfo['archive']}")
                    comm_this.append(generate_extract_command(tinfo['archive'],tfile_path))
                    abs_file=get_absolute_path(tinfo['archive'],tfile_path)
                    sub_file_list='%s %s'%(sub_file_list,abs_file[1:])
                print('\t\t Extract each of the subfile, join them and then you can rename it:\n\t\t\t %s'%(file_path))
                #create the output directory if doesnot exists along with any parent
                out_dir='/'.join(file_path[1:].split('/')[:-1])
                Path(out_dir).mkdir(parents=True, exist_ok=True)
                comm_this.append('cat %s | dd of=%s bs=1M'%(sub_file_list,file_path[1:]))
                comms_dic['large_split'].append(comm_this)
            else:
                #print(archive_info)
                print(f"\t Archive: {archive_info['archive'][0][1]['archive']}")
                comm_this.append(generate_extract_command(archive_info['archive'][0][1]['archive'],archive_info['short_path']))
                #create the output directory if doesnot exists along with any parent
                out_dir='/'.join(file_path[1:].split('/')[:-1])
                Path(out_dir).mkdir(parents=True, exist_ok=True)
                comm_this.append(f"mv {archive_info['short_path'][1:]} {file_path[1:]}")
                comms_dic['large'].append(comm_this)
        elif(ftype=='split'):
            print(f"\t This file was split in {archive_info['num_chunks']} subfiles due to its size")
            sub_file_list=''
            comm_this
            for tt in range(0,archive_info['num_chunks']):
                tfile_path=archive_info['archive%d'%tt][0][0]
                tinfo=archive_info['archive%d'%tt][0][1]
                print(f"\t sub_File: {tfile_path}")
                print(f"\t Archive: {tinfo['archive']}")
                abs_file=get_absolute_path(tinfo['archive'],tfile_path)
                sub_file_list='%s %s'%(sub_file_list,abs_file[1:])
                comm_this.append(generate_extract_command(tinfo['archive'],tfile_path[1:]))
            print('\t Extract each of the subfile, join them and then you can rename it:\n\t\t %s'%(file_path))
            #create the output directory if doesnot exists along with any parent
            out_dir='/'.join(file_path[1:].split('/')[:-1])
            Path(out_dir).mkdir(parents=True, exist_ok=True)
            comm_this.append('cat %s | dd of=%s bs=1M'%(sub_file_list,file_path))
            comms_dic['split'].append(comm_this)
            
    
    return comms_dic

def generate_extract_command(archive,file):
    abs_file=get_absolute_path(archive,file)
    #command to exract a file
    comm='htar -xvf %s %s'%(archive,abs_file)
    
    return comm

def get_absolute_path(archive,file):
    #first we need to find prefix on cfs and tape
    prefix_cfs='/global/cfs/cdirs/desicollab/'
    prefix_tape='/nersc/projects/desi/'
    #path to the directory
    tspl=archive[len(prefix_tape):].split('/')
    tdir=prefix_cfs+'/'.join(tspl[:-1])+'/'
    if(prefix_cfs[1:] in file):
        return file
    else:
        return tdir+file

def print_commands_extract(comms_dic_list,outfile=None):
    '''prints the command to the output for extraction'''
    
    comm_str=''
    for tt,tdic in enumerate(comms_dic_list):
        for ii,ikey in enumerate(tdic.keys()):
            if(tdic[ikey]!=[]):
                comm_str=comm_str+'\n\n#### %s files ####\n'%(ikey)
                for cc,comm in enumerate(tdic[ikey]):
                    if(ikey=='regular'):
                        comm_str=comm_str+comm+'\n'
                    else:
                        for ci,comm_i in enumerate(tdic[ikey][cc]):
                            comm_str=comm_str+comm_i+'\n'
                        comm_str=comm_str+'#\n#\n'
      
    if(outfile is not None):
        with open(outfile,'w') as fout:
            fout.write(comm_str)
        print('\n\n\n ****************\nThe command to extract found file is written in %s'%(outfile))
        print('You can simply execute this file from this directory to actually extract all the files\n ****************\n\n')
    else:
        print('**** all comms_dic ***')
        print(comm_str)
    
    return
    

if __name__ == '__main__':
    main()
